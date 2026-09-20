import Foundation
import MapGrapherCore

@MainActor
final class AppContainer {
    let gateway: SupabaseGateway
    let session: SessionController
    let assetResolver: SupabaseAssetResolver
    let assetLoader: PrivateAssetLoader
    let photoReader: SupabasePhotoReader
    let mapLocationProvider: MapLocationAdapter

    init(gateway: SupabaseGateway) {
        let createdSession = SessionController(auth: SupabaseAuthRepository(client: gateway.client))
        let createdResolver = SupabaseAssetResolver(client: gateway.client, session: createdSession)
        let createdLoader = PrivateAssetLoader(resolver: createdResolver, session: createdSession)
        let createdPhotoReader = SupabasePhotoReader(gateway: gateway, session: createdSession)
        let createdMapLocationProvider = MapLocationAdapter()
        self.gateway = gateway
        session = createdSession
        assetResolver = createdResolver
        assetLoader = createdLoader
        photoReader = createdPhotoReader
        mapLocationProvider = createdMapLocationProvider
        createdSession.onInvalidation = { [weak createdLoader] context in
            await createdLoader?.invalidate(context: context)
        }
    }

    func start() async { await session.start() }

    func onSessionInvalidation(_ handler: @escaping @MainActor @Sendable (SessionContext) async -> Void) {
        let loader = assetLoader
        session.onInvalidation = { [weak loader] context in
            await loader?.invalidate(context: context)
            await handler(context)
        }
    }
}
