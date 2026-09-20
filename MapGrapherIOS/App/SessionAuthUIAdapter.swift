import Foundation
import MapGrapherCore

/// 認証画面とアプリ全体のセッション管理を接続します。
@MainActor
final class SessionAuthUIAdapter: AuthUIService {
    private let session: SessionController

    init(session: SessionController) { self.session = session }

    func signIn(email: String, password: String) async throws -> AuthUIOutcome {
        do {
            try await session.signIn(email: email, password: password)
            return .signedIn
        } catch {
            throw map(error)
        }
    }

    func signInWithGoogle() async throws -> AuthUIOutcome {
        do {
            try await session.signInWithGoogle()
            return .signedIn
        } catch { throw map(error) }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUIOutcome {
        do {
            try await session.signInWithApple(idToken: idToken, nonce: nonce)
            return .signedIn
        } catch { throw map(error) }
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUIOutcome {
        do {
            try await session.signUp(email: email, password: password, displayName: displayName)
            return session.state == .awaitingEmailConfirmation ? .confirmationRequired : .signedIn
        } catch {
            throw map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do { try await session.requestPasswordReset(email: email) }
        catch { throw map(error) }
    }

    private func map(_ error: Error) -> AuthUIError {
        if let failure = error as? AppFailure {
            switch failure {
            case .offline, .serviceUnavailable, .rateLimited: return .serviceUnavailable
            case .needsLogin: return .invalidCredentials
            default: return .unknown
            }
        }
        let description = String(describing: error).lowercased()
        if description.contains("already registered") || description.contains("user already") {
            return .emailAlreadyRegistered
        }
        if description.contains("email not confirmed") { return .emailNotConfirmed }
        if description.contains("invalid login credentials") { return .invalidCredentials }
        return .unknown
    }
}
