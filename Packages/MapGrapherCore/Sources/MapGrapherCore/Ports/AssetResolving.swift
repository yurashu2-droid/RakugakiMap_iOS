import Foundation

public protocol AssetResolving: Sendable {
    func resolve(_ asset: AssetReference, context: SessionContext) async throws -> SignedAsset
    func invalidate(context: SessionContext) async
}
