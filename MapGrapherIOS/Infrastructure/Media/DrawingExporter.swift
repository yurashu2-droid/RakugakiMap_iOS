import CryptoKit
import Foundation
import ImageIO
import MapGrapherCore
import UniformTypeIdentifiers

enum DrawingExportError: Error {
    case outputUnavailable
    case outputTooLarge
}

struct DrawingExporter: Sendable {
    let outputDirectory: URL

    func export(document: DrawingDocument) async throws -> PreparedImage {
        let directory = outputDirectory
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
            let output = directory.appendingPathComponent(UUID().uuidString + ".png")
            do {
                let image = try DrawingRenderer().render(document: document)
                guard let destination = CGImageDestinationCreateWithURL(
                    temporary as CFURL, UTType.png.identifier as CFString, 1, nil
                ) else { throw DrawingExportError.outputUnavailable }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw DrawingExportError.outputUnavailable
                }
                try Task.checkCancellation()
                let data = try Data(contentsOf: temporary)
                guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
                    throw DrawingExportError.outputTooLarge
                }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                try FileManager.default.moveItem(at: temporary, to: output)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: output.path
                )
                guard let prepared = PreparedImage(fileURL: output, mimeType: "image/png",
                                                   byteSize: Int64(data.count),
                                                   pixelWidth: document.pixelWidth,
                                                   pixelHeight: document.pixelHeight,
                                                   sha256: hash) else {
                    throw DrawingExportError.outputUnavailable
                }
                return prepared
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }.value
    }
}
