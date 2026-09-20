import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

@MainActor
struct WelcomeScreen: View {
    let service: any AuthUIService
    let onSignedIn: @MainActor () -> Void
    @State private var providerError: String?
    @State private var appleNonce = ""
    @State private var providerBusy = false

    init(
        service: any AuthUIService = FakeAuthUIService(),
        onSignedIn: @escaping @MainActor () -> Void = {}
    ) {
        self.service = service
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    VStack(spacing: AppSpacing.medium) {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(AppColors.coral)
                            .accessibilityHidden(true)

                        Text(AuthStrings.welcomeTitle)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppColors.ink)
                            .multilineTextAlignment(.center)

                        Text(AuthStrings.welcomeDetail)
                            .font(.body)
                            .foregroundStyle(AppColors.ink.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: AppSpacing.medium) {
                        Button {
                            guard !providerBusy else { return }
                            providerBusy = true
                            providerError = nil
                            Task {
                                defer { providerBusy = false }
                                do {
                                    _ = try await service.signInWithGoogle()
                                    onSignedIn()
                                } catch {
                                    providerError = "Googleログインを完了できませんでした。設定と通信状態を確認してください。"
                                }
                            }
                        } label: {
                            Text("Googleで続ける")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .disabled(providerBusy)
                        .accessibilityIdentifier("auth.google")

                        SignInWithAppleButton(.continue, onRequest: { request in
                            appleNonce = Self.makeNonce()
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = Self.sha256(appleNonce)
                        }, onCompletion: { result in
                            guard !providerBusy else { return }
                            switch result {
                            case .success(let authorization):
                                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                      let data = credential.identityToken,
                                      let token = String(data: data, encoding: .utf8),
                                      !appleNonce.isEmpty else {
                                    providerError = "Appleログインの認証情報を取得できませんでした。"
                                    return
                                }
                                let nonce = appleNonce
                                appleNonce = ""
                                providerBusy = true
                                Task {
                                    defer { providerBusy = false }
                                    do {
                                        _ = try await service.signInWithApple(idToken: token, nonce: nonce)
                                        onSignedIn()
                                    } catch {
                                        providerError = "Appleログインを完了できませんでした。設定と通信状態を確認してください。"
                                    }
                                }
                            case .failure:
                                appleNonce = ""
                                providerError = "Appleログインを完了できませんでした。"
                            }
                        })
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .disabled(providerBusy)
                        .accessibilityIdentifier("auth.apple")

                        if let providerError {
                            Text(providerError)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("auth.provider-error")
                        }

                        NavigationLink {
                            SignInScreen(service: service, onSignedIn: onSignedIn)
                        } label: {
                            Text(AuthStrings.signIn)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .accessibilityIdentifier("auth.sign-in")

                        NavigationLink {
                            SignUpScreen(service: service, onSignedIn: onSignedIn)
                        } label: {
                            Text(AuthStrings.signUp)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityIdentifier("auth.sign-up")

                        NavigationLink {
                            PasswordResetScreen(service: service)
                        } label: {
                            Text(AuthStrings.passwordReset)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("auth.password-reset")
                    }
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.vertical, AppSpacing.section)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AuthStrings.welcomeTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("screen.auth.welcome")
        .accessibilityLabel(Text(AuthStrings.welcomeTitle))
    }

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return ""
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
