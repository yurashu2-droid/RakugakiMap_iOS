import Foundation
import Supabase
import AuthenticationServices
import UIKit

@MainActor
final class SupabaseAuthRepository: AuthSessionServicing {
    private let client: SupabaseClient
    private let webAuthentication = WebAuthenticationSession()

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

    func signInWithGoogle() async throws -> UUID {
        let redirect = URL(string: "rakugakimap-dev://auth/callback")!
        let url = try await client.auth.getOAuthSignInURL(provider: .google, redirectTo: redirect)
        let callback = try await webAuthentication.authenticate(url: url, callbackScheme: redirect.scheme!)
        guard AuthLinkHandler(redirectURL: redirect).flow(for: callback) == .code else {
            throw AuthWebError.invalidCallback
        }
        return try await client.auth.session(from: callback).user.id
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        guard !idToken.isEmpty, !nonce.isEmpty else { throw AuthWebError.invalidCallback }
        return try await client.auth.signInWithIdToken(credentials:
            OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)).user.id
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

private enum AuthWebError: Error { case invalidCallback, couldNotStart }

@MainActor
private final class WebAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) {
                callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: AuthWebError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: AuthWebError.couldNotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
