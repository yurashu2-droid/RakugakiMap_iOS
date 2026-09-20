import Foundation
import UIKit
import MapGrapherCore

protocol AssetClock: Sendable {
    func now() -> Date
}

struct SystemAssetClock: AssetClock {
    func now() -> Date { Date() }
}

/// URLや画像をディスクへ保存しない、セッション別の容量制限付き画像キャッシュ。
@MainActor
final class AccountImageCache {
    private final class Entry: NSObject {
        let image: UIImage
        let expiresAt: Date
        init(image: UIImage, expiresAt: Date) {
            self.image = image
            self.expiresAt = expiresAt
        }
    }

    private let images = NSCache<NSString, Entry>()
    private var keysByContext: [SessionKey: Set<CacheKey>] = [:]
    private var revisions: [SessionKey: UInt64] = [:]

    init(maximumBytes: Int = 64 * 1024 * 1024) {
        images.totalCostLimit = maximumBytes
        images.countLimit = 100
    }

    func revision(for context: SessionContext) -> UInt64 {
        revisions[SessionKey(context), default: 0]
    }

    func image(for asset: AssetReference, context: SessionContext,
               width: Int, height: Int, now: Date) -> UIImage? {
        let key = CacheKey(asset: asset, context: context, width: width, height: height)
        guard let entry = images.object(forKey: key.cacheString as NSString) else { return nil }
        guard now < entry.expiresAt.addingTimeInterval(-60) else {
            images.removeObject(forKey: key.cacheString as NSString)
            return nil
        }
        return entry.image
    }

    func insert(_ image: UIImage, asset: AssetReference, context: SessionContext,
                width: Int, height: Int, expiresAt: Date) {
        let key = CacheKey(asset: asset, context: context, width: width, height: height)
        let cost = max(1, image.cgImage?.bytesPerRow ?? width * 4) * max(1, image.cgImage?.height ?? height)
        images.setObject(Entry(image: image, expiresAt: expiresAt),
                         forKey: key.cacheString as NSString, cost: cost)
        keysByContext[SessionKey(context), default: []].insert(key)
    }

    func invalidate(asset: AssetReference, context: SessionContext) {
        let owner = SessionKey(context)
        revisions[owner] = (revisions[owner] ?? 0) &+ 1
        guard let keys = keysByContext[owner] else { return }
        for key in keys where key.bucket == asset.bucket && key.path == asset.path {
            images.removeObject(forKey: key.cacheString as NSString)
            keysByContext[owner]?.remove(key)
        }
    }

    func invalidate(context: SessionContext) {
        let owner = SessionKey(context)
        revisions[owner] = (revisions[owner] ?? 0) &+ 1
        for key in keysByContext.removeValue(forKey: owner) ?? [] {
            images.removeObject(forKey: key.cacheString as NSString)
        }
    }

    private struct SessionKey: Hashable {
        let userID: UUID
        let epoch: UUID
        init(_ context: SessionContext) {
            userID = context.userID
            epoch = context.epoch
        }
    }

    private struct CacheKey: Hashable {
        let session: SessionKey
        let bucket: String
        let path: String
        let width: Int
        let height: Int

        init(asset: AssetReference, context: SessionContext, width: Int, height: Int) {
            session = SessionKey(context)
            bucket = asset.bucket
            path = asset.path
            self.width = width
            self.height = height
        }

        var cacheString: String {
            "\(session.userID.uuidString)|\(session.epoch.uuidString)|\(bucket.count):\(bucket)|\(path.count):\(path)|\(width)x\(height)"
        }
    }
}
