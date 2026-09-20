import Foundation
import Supabase

@MainActor
final class SupabaseAuthRepository: AuthSessionServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    var events: AsyncStream<AuthSessionState> {
        let client = self.client
        let sdkEvents = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in sdkEvents {
                    switch event {
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                        if let session, !session.isExpired {
                            continuation.yield(.authenticated(session.user.id))
                        } else if session != nil {
                            continuation.yield(.reauthenticationRequired)
                        } else {
                            continuation.yield(client.auth.currentSession == nil
                                ? .signedOut : .reauthenticationRequired)
                        }
                    case .signedOut:
                        continuation.yield(.signedOut)
                    default: break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restore() async -> AuthSessionState {
        do { return .authenticated(try await client.auth.session.user.id) }
        catch { return client.auth.currentSession == nil ? .signedOut : .reauthenticationRequired }
    }

    func signIn(email: String, password: String) async throws -> UUID {
        try await client.auth.signIn(email: email, password: password).user.id
    }

    func signUp(email: String, password: String, displayName: String) async throws -> UUID? {
        let response = try await client.auth.signUp(email: email, password: password,
                                                     data: ["display_name": .string(displayName)],
                                                     redirectTo: URL(string: "rakugakimap-dev://auth/callback"))
        return response.session?.user.id
    }

    func signOut() async throws { try await client.auth.signOut() }

    func requestPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email,
            redirectTo: URL(string: "rakugakimap-dev://auth/callback"))
    }

    func completeAuthURL(_ url: URL) async throws -> UUID {
        try await client.auth.session(from: url).user.id
    }
}
