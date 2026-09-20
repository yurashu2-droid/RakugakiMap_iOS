import Foundation
import Supabase
import MapGrapherCore

protocol SignedURLIssuing: Sendable {
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL
}

private struct SupabaseStorageSigner: SignedURLIssuing {
    let client: SupabaseClient
    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: expiresIn)
    }
}

/// Storageの認可を通る署名URLのみ発行する。URLはセッションを跨いで再利用しない。
actor SupabaseAssetResolver: AssetResolving {
    private struct Key: Hashable {
        let userID: UUID
        let epoch: UUID
        let bucket: String
        let path: String
        init(asset: AssetReference, context: SessionContext) {
            userID = context.userID
            epoch = context.epoch
            bucket = asset.bucket
            path = asset.path
        }
    }

    private struct ContextKey: Hashable {
        let userID: UUID
        let epoch: UUID
        init(_ context: SessionContext) {
            userID = context.userID
            epoch = context.epoch
        }
    }

    private let signer: any SignedURLIssuing
    private let session: any SessionProviding
    private let clock: any AssetClock
    private var signedURLs: [Key: SignedAsset] = [:]
    private var revisions: [ContextKey: UInt64] = [:]
    private let ttlSeconds = 300

    init(client: SupabaseClient, session: any SessionProviding,
         clock: any AssetClock = SystemAssetClock()) {
        self.signer = SupabaseStorageSigner(client: client)
        self.session = session
        self.clock = clock
    }

    init(signer: any SignedURLIssuing, session: any SessionProviding,
         clock: any AssetClock = SystemAssetClock()) {
        self.signer = signer
        self.session = session
        self.clock = clock
    }

    func resolve(_ asset: AssetReference, context: SessionContext) async throws -> SignedAsset {
        guard ["photos", "rakugakis", "avatars"].contains(asset.bucket) else {
            throw AppFailure.validation("画像の保存先が不正です")
        }
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
        try Task.checkCancellation()
        let key = Key(asset: asset, context: context)
        let owner = ContextKey(context)
        let revision = revisions[owner, default: 0]
        let now = clock.now()
        if let cached = signedURLs[key],
           cached.isUsable(for: context, now: now),
           now < cached.expiresAt.addingTimeInterval(-60) {
            return cached
        }
        let url: URL
        do { url = try await signer.signedURL(bucket: asset.bucket, path: asset.path,
                                              expiresIn: ttlSeconds) }
        catch { throw Self.map(error) }
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
        guard revisions[owner, default: 0] == revision else { throw AppFailure.cancelled }
        guard url.scheme == "https", url.host != nil else { throw AppFailure.serviceUnavailable }
        let signed = SignedAsset(url: url, expiresAt: clock.now().addingTimeInterval(TimeInterval(ttlSeconds)),
                                 context: context)
        signedURLs[key] = signed
        return signed
    }

    func invalidate(context: SessionContext) async {
        let owner = ContextKey(context)
        revisions[owner] = (revisions[owner] ?? 0) &+ 1
        signedURLs = signedURLs.filter {
            !($0.key.userID == context.userID && $0.key.epoch == context.epoch)
        }
    }

    private static func map(_ error: Error) -> AppFailure {
        if let known = error as? AppFailure { return known }
        if error is CancellationError { return .cancelled }
        if let storage = error as? StorageError {
            switch storage.statusCode {
            case "401": return .needsLogin
            case "403": return .forbidden
            case "404": return .notFound
            case "429": return .rateLimited
            default: return .serviceUnavailable
            }
        }
        if error is URLError { return .offline }
        return .serviceUnavailable
    }
}
