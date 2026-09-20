import Foundation

/// 認証画面が必要とする最小の境界です。Supabase SDKやtokenはこの層へ持ち込みません。
@MainActor
protocol AuthUIService {
    func signIn(email: String, password: String) async throws -> AuthUIOutcome
    func signInWithGoogle() async throws -> AuthUIOutcome
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUIOutcome
    func signUp(email: String, password: String, displayName: String) async throws -> AuthUIOutcome
    func sendPasswordReset(email: String) async throws
}

enum AuthUIOutcome: Equatable, Sendable {
    case signedIn
    case confirmationRequired
}

enum AuthUIError: Error, Equatable, Sendable {
    case invalidEmail
    case invalidDisplayName
    case invalidPassword
    case passwordMismatch
    case invalidCredentials
    case emailAlreadyRegistered
    case emailNotConfirmed
    case serviceUnavailable
    case unknown
}

/// UIテスト、Preview、認証adapter未接続時に使う決定的なfakeです。
@MainActor
final class FakeAuthUIService: AuthUIService {
    var signInResult: Result<AuthUIOutcome, AuthUIError>
    var signUpResult: Result<AuthUIOutcome, AuthUIError>
    var passwordResetResult: Result<Void, AuthUIError>

    init(
        signInResult: Result<AuthUIOutcome, AuthUIError> = .success(.signedIn),
        signUpResult: Result<AuthUIOutcome, AuthUIError> = .success(.confirmationRequired),
        passwordResetResult: Result<Void, AuthUIError> = .success(())
    ) {
        self.signInResult = signInResult
        self.signUpResult = signUpResult
        self.passwordResetResult = passwordResetResult
    }

    func signIn(email: String, password: String) async throws -> AuthUIOutcome {
        try signInResult.get()
    }

    func signInWithGoogle() async throws -> AuthUIOutcome { try signInResult.get() }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUIOutcome {
        try signInResult.get()
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthUIOutcome {
        try signUpResult.get()
    }

    func sendPasswordReset(email: String) async throws {
        try passwordResetResult.get()
    }
}
