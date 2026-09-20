import Foundation
import UIKit
import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class PrivateAssetLoaderTests: XCTestCase {
    private let asset = AssetReference(bucket: "photos", path: "synthetic/photos/photo.png")!

    func testSignedURLRefreshesAtSixtySecondBoundary() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let clock = FakeAssetClock(now: Date(timeIntervalSince1970: 1_000))
        let signer = FakeSignedURLIssuer()
        let resolver = SupabaseAssetResolver(signer: signer, session: session, clock: clock)

        _ = try await resolver.resolve(asset, context: context)
        clock.advance(239)
        _ = try await resolver.resolve(asset, context: context)
        let firstCount = await signer.callCount
        XCTAssertEqual(firstCount, 1)
        clock.advance(1)
        _ = try await resolver.resolve(asset, context: context)
        let secondCount = await signer.callCount
        let requestedTTL = await signer.requestedTTL
        XCTAssertEqual(secondCount, 2)
        XCTAssertEqual(requestedTTL, [300, 300])
    }

    func testSamePathDifferentAccountDoesNotShareImage() async throws {
        let a = SessionContext(userID: UUID(), epoch: UUID())
        let b = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: a)
        let resolver = FakeAssetResolver()
        let downloader = FakeImageDownloader(results: [.success(png(.red)), .success(png(.blue))])
        let loader = PrivateAssetLoader(resolver: resolver, session: session, downloader: downloader)
        let first = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: a)
        await session.set(b)
        let second = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: b)
        await loader.invalidate(context: a)
        let secondAgain = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: b)
        let downloadCount = await downloader.callCount
        XCTAssertEqual(downloadCount, 2)
        XCTAssertNotEqual(first.pngData(), second.pngData())
        XCTAssertEqual(second.pngData(), secondAgain.pngData())
        XCTAssertLessThanOrEqual(first.size.width, 16)
    }

    func testCachedImageExpiresBeforeSignedURL() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let clock = FakeAssetClock(now: Date(timeIntervalSince1970: 1_000))
        let resolver = FakeAssetResolver(clock: clock)
        let downloader = FakeImageDownloader(results: [.success(png(.red)), .success(png(.blue))])
        let loader = PrivateAssetLoader(resolver: resolver, session: session,
                                        downloader: downloader, clock: clock)
        _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: context)
        clock.advance(239)
        _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: context)
        let beforeBoundary = await downloader.callCount
        XCTAssertEqual(beforeBoundary, 1)
        clock.advance(1)
        _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 16, height: 16), context: context)
        let afterBoundary = await downloader.callCount
        XCTAssertEqual(afterBoundary, 2)
    }

    func testForbiddenDownloadResignsOnceAndRetriesOnce() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let resolver = FakeAssetResolver()
        let downloader = FakeImageDownloader(results: [
            .failure(AssetDownloadError.httpStatus(403)), .success(png(.green))
        ])
        let loader = PrivateAssetLoader(resolver: resolver, session: session, downloader: downloader)
        _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 8, height: 8), context: context)
        let downloadCount = await downloader.callCount
        let invalidateCount = await resolver.invalidateCount
        XCTAssertEqual(downloadCount, 2)
        XCTAssertEqual(invalidateCount, 1)
    }

    func testSecondForbiddenFailureStopsWithoutPublicFallback() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let resolver = FakeAssetResolver()
        let downloader = FakeImageDownloader(results: [
            .failure(AssetDownloadError.httpStatus(403)),
            .failure(AssetDownloadError.httpStatus(403))
        ])
        let loader = PrivateAssetLoader(resolver: resolver, session: session, downloader: downloader)
        do {
            _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 8, height: 8), context: context)
            XCTFail("権限外の画像を表示してはいけません")
        } catch let error as AppFailure {
            XCTAssertEqual(error, .forbidden)
        }
        let downloadCount = await downloader.callCount
        XCTAssertEqual(downloadCount, 2)
    }

    func testNotFoundDownloadRechecksStoragePermissionOnce() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let resolver = FakeAssetResolver()
        let downloader = FakeImageDownloader(results: [
            .failure(AssetDownloadError.httpStatus(404)),
            .failure(AssetDownloadError.httpStatus(404))
        ])
        let loader = PrivateAssetLoader(resolver: resolver, session: session, downloader: downloader)
        do {
            _ = try await loader.load(asset: asset, targetPixelSize: CGSize(width: 8, height: 8), context: context)
            XCTFail("存在しない画像を表示してはいけません")
        } catch let error as AppFailure {
            XCTAssertEqual(error, .notFound)
        }
        let count = await downloader.callCount
        XCTAssertEqual(count, 2)
    }

    func testLogoutWhileDownloadIsSuspendedDiscardsOldResult() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let resolver = FakeAssetResolver()
        let downloader = SuspendedImageDownloader()
        let loader = PrivateAssetLoader(resolver: resolver, session: session, downloader: downloader)
        let load = Task {
            try await loader.load(asset: asset, targetPixelSize: CGSize(width: 8, height: 8), context: context)
        }
        await downloader.waitUntilStarted()
        await session.set(nil)
        await loader.invalidate(context: context)
        await downloader.finish(with: png(.red))
        do {
            _ = try await load.value
            XCTFail("logout後の結果を返してはいけません")
        } catch let error as AppFailure {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testCacheInvalidationDuringDownloadDoesNotReinsertImage() async throws {
        let context = SessionContext(userID: UUID(), epoch: UUID())
        let session = FakeAssetSession(context: context)
        let downloader = SuspendedImageDownloader()
        let loader = PrivateAssetLoader(resolver: FakeAssetResolver(), session: session,
                                        downloader: downloader)
        let load = Task {
            try await loader.load(asset: asset, targetPixelSize: CGSize(width: 8, height: 8), context: context)
        }
        await downloader.waitUntilStarted()
        await loader.invalidate(context: context)
        await downloader.finish(with: png(.green))
        do {
            _ = try await load.value
            XCTFail("失効した結果を再キャッシュしてはいけません")
        } catch let error as AppFailure {
            XCTAssertEqual(error, .cancelled)
        }
    }

    private func png(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).pngData { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}

private actor FakeAssetSession: SessionProviding {
    private var context: SessionContext?
    init(context: SessionContext?) { self.context = context }
    func currentContext() async -> SessionContext? { context }
    func isCurrent(_ candidate: SessionContext) async -> Bool { context == candidate }
    func set(_ context: SessionContext?) { self.context = context }
}

private final class FakeAssetClock: AssetClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(now: Date) { value = now }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}

private actor FakeSignedURLIssuer: SignedURLIssuing {
    private(set) var callCount = 0
    private(set) var requestedTTL: [Int] = []
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        callCount += 1
        requestedTTL.append(expiresIn)
        return URL(string: "https://example.invalid/signed/\(callCount)")!
    }
}

private actor FakeAssetResolver: AssetResolving {
    private(set) var invalidateCount = 0
    private let clock: any AssetClock
    init(clock: any AssetClock = SystemAssetClock()) { self.clock = clock }
    func resolve(_ asset: AssetReference, context: SessionContext) async throws -> SignedAsset {
        SignedAsset(url: URL(string: "https://example.invalid/private")!,
                    expiresAt: clock.now().addingTimeInterval(300), context: context)
    }
    func invalidate(context: SessionContext) async { invalidateCount += 1 }
}

private actor FakeImageDownloader: PrivateImageDownloading {
    private var results: [Result<Data, Error>]
    private(set) var callCount = 0
    init(results: [Result<Data, Error>]) { self.results = results }
    func download(_ url: URL) async throws -> Data {
        callCount += 1
        guard !results.isEmpty else { throw AppFailure.serviceUnavailable }
        return try results.removeFirst().get()
    }
}

private actor SuspendedImageDownloader: PrivateImageDownloading {
    private var pending: CheckedContinuation<Data, Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func download(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { continuation in startWaiter = continuation }
    }
    func finish(with data: Data) {
        pending?.resume(returning: data)
        pending = nil
    }
}
