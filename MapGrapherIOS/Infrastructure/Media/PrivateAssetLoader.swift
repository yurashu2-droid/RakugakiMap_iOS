import Foundation
import ImageIO
import UIKit
import MapGrapherCore

enum AssetDownloadError: Error, Sendable {
    case httpStatus(Int)
}

protocol PrivateImageDownloading: Sendable {
    func download(_ url: URL) async throws -> Data
}

struct URLSessionImageDownloader: PrivateImageDownloading {
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await Self.privateSession.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw AppFailure.serviceUnavailable }
        guard (200...299).contains(http.statusCode) else {
            throw AssetDownloadError.httpStatus(http.statusCode)
        }
        return data
    }
}

private struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}

@MainActor
final class PrivateAssetLoader {
    private let resolver: any AssetResolving
    private let session: any SessionProviding
    private let downloader: any PrivateImageDownloading
    private let cache: AccountImageCache
    private let clock: any AssetClock

    init(resolver: any AssetResolving, session: any SessionProviding,
         downloader: any PrivateImageDownloading = URLSessionImageDownloader(),
         cache: AccountImageCache = AccountImageCache(),
         clock: any AssetClock = SystemAssetClock()) {
        self.resolver = resolver
        self.session = session
        self.downloader = downloader
        self.cache = cache
        self.clock = clock
    }

    func load(asset: AssetReference, targetPixelSize: CGSize,
              context: SessionContext) async throws -> UIImage {
        guard targetPixelSize.width.isFinite, targetPixelSize.height.isFinite,
              targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            throw AppFailure.validation("画像サイズが不正です")
        }
        let width = max(1, Int(min(4_096, ceil(targetPixelSize.width))))
        let height = max(1, Int(min(4_096, ceil(targetPixelSize.height))))
        try await checkContext(context)
        var cacheRevision = cache.revision(for: context)
        if let cached = cache.image(for: asset, context: context,
                                    width: width, height: height, now: clock.now()) {
            return cached
        }

        var signed = try await resolver.resolve(asset, context: context)
        try await checkContext(context)
        let data: Data
        do {
            data = try await downloader.download(signed.url)
        } catch AssetDownloadError.httpStatus(let status) where status == 403 || status == 404 {
            cache.invalidate(asset: asset, context: context)
            cacheRevision = cache.revision(for: context)
            await resolver.invalidate(context: context)
            try await checkContext(context)
            signed = try await resolver.resolve(asset, context: context)
            try await checkContext(context)
            do { data = try await downloader.download(signed.url) }
            catch { throw Self.mapDownload(error) }
        } catch { throw Self.mapDownload(error) }

        try await checkContext(context)
        let decoded = try await Task.detached(priority: .utility) {
            try Self.downsample(data: data, maximumPixelSize: max(width, height))
        }.value
        try await checkContext(context)
        guard cache.revision(for: context) == cacheRevision else { throw AppFailure.cancelled }
        let image = UIImage(cgImage: decoded.cgImage)
        cache.insert(image, asset: asset, context: context,
                     width: width, height: height, expiresAt: signed.expiresAt)
        return image
    }

    func invalidate(context: SessionContext) async {
        cache.invalidate(context: context)
        await resolver.invalidate(context: context)
    }

    private func checkContext(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }

    private nonisolated static func downsample(data: Data, maximumPixelSize: Int) throws -> DecodedImage {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw AppFailure.validation("画像データが不正です") }
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
           let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int {
            guard sourceWidth > 0, sourceHeight > 0,
                  sourceWidth <= 20_000, sourceHeight <= 20_000,
                  Int64(sourceWidth) * Int64(sourceHeight) <= 100_000_000 else {
                throw AppFailure.validation("画像サイズが不正です")
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppFailure.validation("画像を開けません")
        }
        return DecodedImage(cgImage: image)
    }

    private static func mapDownload(_ error: Error) -> AppFailure {
        if let known = error as? AppFailure { return known }
        if error is CancellationError { return .cancelled }
        if let download = error as? AssetDownloadError {
            switch download {
            case .httpStatus(401): return .needsLogin
            case .httpStatus(403): return .forbidden
            case .httpStatus(404): return .notFound
            case .httpStatus(429): return .rateLimited
            default: return .serviceUnavailable
            }
        }
        if error is URLError { return .offline }
        return .serviceUnavailable
    }
}
