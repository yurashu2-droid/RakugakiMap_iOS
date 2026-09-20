import CryptoKit
import Foundation
import ImageIO
import MapGrapherCore
import UniformTypeIdentifiers

enum ImagePreparationError: Error {
    case invalidImage
    case dimensionsTooLarge
    case outputTooLarge
    case metadataRemovalFailed
    case outputFailed
}

struct ImagePreparer: Sendable {
    let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func prepare(input: URL) async throws -> PreparedImage {
        let directory = outputDirectory
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try Self.prepareSynchronously(input: input, outputDirectory: directory)
        }
        return try await withTaskCancellationHandler {
            let prepared = try await work.value
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: prepared.fileURL)
                throw CancellationError()
            }
            return prepared
        } onCancel: {
            work.cancel()
        }
    }

    private static func prepareSynchronously(input: URL, outputDirectory: URL) throws -> PreparedImage {
        guard input.isFileURL,
              let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw ImagePreparationError.invalidImage
        }
        guard width <= 20_000, height <= 20_000,
              Int64(width) * Int64(height) <= 100_000_000 else {
            throw ImagePreparationError.dimensionsTooLarge
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let normalized = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePreparationError.invalidImage
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let temporary = outputDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        let output = outputDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            guard let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil
            ) else { throw ImagePreparationError.outputFailed }
            // 入力元のメタデータを合成せず、位置情報とXMPも出力側で明示的に除外する。
            CGImageDestinationAddImage(destination, normalized, [
                kCGImageDestinationLossyCompressionQuality: 0.8,
                kCGImageDestinationMergeMetadata: false,
                kCGImageMetadataShouldExcludeGPS: true,
                kCGImageMetadataShouldExcludeXMP: true
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImagePreparationError.outputFailed }
            guard !ImageMetadataInspector.hasSensitiveMetadata(at: temporary) else {
                throw ImagePreparationError.metadataRemovalFailed
            }
            let data = try Data(contentsOf: temporary)
            guard data.count <= 20 * 1024 * 1024 else { throw ImagePreparationError.outputTooLarge }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: output)
            guard let prepared = PreparedImage(fileURL: output, mimeType: "image/jpeg",
                                               byteSize: Int64(data.count),
                                               pixelWidth: normalized.width,
                                               pixelHeight: normalized.height,
                                               sha256: hash) else {
                throw ImagePreparationError.outputFailed
            }
            try Task.checkCancellation()
            return prepared
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
