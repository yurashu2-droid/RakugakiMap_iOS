import Foundation
import MapGrapherCore

@MainActor
final class AppContainer {
    let session: SessionController

    init(gateway: SupabaseGateway) {
        session = SessionController(auth: SupabaseAuthRepository(client: gateway.client))
    }

    func start() async { await session.start() }

    func onSessionInvalidation(_ handler: @escaping @MainActor @Sendable (SessionContext) async -> Void) {
        session.onInvalidation = handler
    }
}
