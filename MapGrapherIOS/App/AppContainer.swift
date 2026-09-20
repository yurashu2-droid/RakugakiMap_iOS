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
    let arRepository: ARRepository
    let groupsService: SupabaseGroupsService
    private var postingServices: [UUID: LazyPostingUIService] = [:]
    private var socialServices: [UUID: SupabaseSocialProfileService] = [:]
    private var photoDetailServices: [UUID: SupabasePhotoDetailService] = [:]

    init(gateway: SupabaseGateway) {
        let createdSession = SessionController(auth: SupabaseAuthRepository(client: gateway.client))
        let createdResolver = SupabaseAssetResolver(client: gateway.client, session: createdSession)
        let createdLoader = PrivateAssetLoader(resolver: createdResolver, session: createdSession)
        let createdPhotoReader = SupabasePhotoReader(gateway: gateway, session: createdSession)
        let createdMapLocationProvider = MapLocationAdapter()
        let createdARRepository = ARRepository(gateway: gateway, photos: createdPhotoReader,
                                               session: createdSession)
        let createdGroupsService = SupabaseGroupsService(gateway: gateway,
                                                         session: createdSession)
        self.gateway = gateway
        session = createdSession
        assetResolver = createdResolver
        assetLoader = createdLoader
        photoReader = createdPhotoReader
        mapLocationProvider = createdMapLocationProvider
        arRepository = createdARRepository
        groupsService = createdGroupsService
        createdSession.onInvalidation = { [weak createdLoader, weak self] context in
            await createdLoader?.invalidate(context: context)
            self?.postingServices.removeValue(forKey: context.epoch)
            self?.socialServices.removeValue(forKey: context.epoch)
            self?.photoDetailServices.removeValue(forKey: context.epoch)
        }
    }

    func start() async { await session.start() }

    func postingService(for context: SessionContext) -> any PostingUIService {
        if let existing = postingServices[context.epoch] { return existing }
        let created = LazyPostingUIService(context: context, gateway: gateway,
                                           session: session, photoReader: photoReader,
                                           assetLoader: assetLoader)
        postingServices[context.epoch] = created
        return created
    }

    func existingPhotoRakugakiService(for context: SessionContext) -> any ExistingPhotoRakugakiServing {
        if let existing = postingServices[context.epoch] { return existing }
        _ = postingService(for: context)
        return postingServices[context.epoch]!
    }

    func socialService(for context: SessionContext) -> any SocialProfileUIService {
        if let existing = socialServices[context.epoch] { return existing }
        let created = SupabaseSocialProfileService(gateway: gateway, session: session)
        socialServices[context.epoch] = created
        return created
    }

    func photoDetailService(for context: SessionContext) -> any PhotoDetailUIService {
        if let existing = photoDetailServices[context.epoch] { return existing }
        let created = SupabasePhotoDetailService(gateway: gateway, session: session,
                                                 assetLoader: assetLoader)
        photoDetailServices[context.epoch] = created
        return created
    }

    func onSessionInvalidation(_ handler: @escaping @MainActor @Sendable (SessionContext) async -> Void) {
        let loader = assetLoader
        session.onInvalidation = { [weak loader, weak self] context in
            await loader?.invalidate(context: context)
            self?.postingServices.removeValue(forKey: context.epoch)
            self?.socialServices.removeValue(forKey: context.epoch)
            self?.photoDetailServices.removeValue(forKey: context.epoch)
            await handler(context)
        }
    }
}
