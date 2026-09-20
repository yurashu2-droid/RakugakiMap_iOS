import Foundation
import Observation
import MapGrapherCore

enum AuthSessionState: Equatable, Sendable {
    case signedOut
    case authenticated(UUID)
    case reauthenticationRequired
}

@MainActor
protocol AuthSessionServicing: AnyObject {
    var events: AsyncStream<AuthSessionState> { get }
    func restore() async -> AuthSessionState
    func signIn(email: String, password: String) async throws -> UUID
    func signUp(email: String, password: String, displayName: String) async throws -> UUID?
    func signOut() async throws
    func requestPasswordReset(email: String) async throws
    func completeAuthURL(_ url: URL) async throws -> UUID
}

enum SessionState: Equatable {
    case restoring, signedOut, awaitingEmailConfirmation, authenticated(UUID), reauthenticationRequired
}

@MainActor @Observable
final class SessionController: SessionProviding {
    private(set) var state: SessionState = .restoring
    private(set) var context: SessionContext?
    private let auth: any AuthSessionServicing
    private let linkHandler: AuthLinkHandler
    private var listeningTask: Task<Void, Never>?
    private var generation = 0
    private var acceptsEvents = true
    var onInvalidation: (@MainActor @Sendable (SessionContext) async -> Void)?

    init(auth: any AuthSessionServicing,
         redirectURL: URL = URL(string: "rakugakimap-dev://auth/callback")!) {
        self.auth = auth
        self.linkHandler = AuthLinkHandler(redirectURL: redirectURL)
    }

    func start() async {
        guard listeningTask == nil else { return }
        let events = auth.events
        listeningTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.receive(event)
            }
        }
        let revision = generation
        let restored = await auth.restore()
        guard revision == generation else { return }
        await receive(restored)
    }

    func signIn(email: String, password: String) async throws {
        acceptsEvents = true
        let revision = generation
        let userID = try await auth.signIn(email: email, password: password)
        guard revision == generation else { return }
        await receive(.authenticated(userID))
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        acceptsEvents = true
        let revision = generation
        let userID = try await auth.signUp(email: email, password: password, displayName: displayName)
        guard revision == generation else { return }
        if let userID { await receive(.authenticated(userID)) }
        else {
            await invalidate()
            state = .awaitingEmailConfirmation
        }
    }

    func signOut() async throws {
        generation += 1
        acceptsEvents = false
        await invalidate()
        state = .signedOut
        try await auth.signOut()
    }

    func requestPasswordReset(email: String) async throws {
        try await auth.requestPasswordReset(email: email)
    }

    func handleAuthURL(_ url: URL) async throws {
        guard let flow = linkHandler.flow(for: url) else { throw AppFailure.validation("認証リンクが無効です") }
        guard flow == .code else { throw AppFailure.needsLogin }
        let revision = generation
        let userID = try await auth.completeAuthURL(url)
        guard revision == generation else { return }
        acceptsEvents = true
        await receive(.authenticated(userID))
    }

    func currentContext() async -> SessionContext? { context }
    func isCurrent(_ candidate: SessionContext) async -> Bool { context == candidate }

    private func receive(_ event: AuthSessionState) async {
        guard acceptsEvents else { return }
        switch event {
        case .authenticated(let userID):
            if context?.userID != userID {
                await invalidate()
                context = SessionContext(userID: userID, epoch: UUID())
            }
            state = .authenticated(userID)
        case .signedOut:
            await invalidate()
            state = .signedOut
        case .reauthenticationRequired:
            await invalidate()
            state = .reauthenticationRequired
        }
    }

    private func invalidate() async {
        guard let old = context else { return }
        context = nil
        await onInvalidation?(old)
    }

    deinit { listeningTask?.cancel() }
}
