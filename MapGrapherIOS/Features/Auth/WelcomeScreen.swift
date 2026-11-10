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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                        Spacer(minLength: AppSpacing.xLarge)
                        actions
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }
            .background(AppColors.paper.ignoresSafeArea())
            // 最初の画面は題名の帯を出さない（大きな題名と二重になるため）
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AppColors.link)
        .accessibilityIdentifier("screen.auth.welcome")
        .accessibilityLabel(Text(AuthStrings.welcomeTitle))
    }

    // 画面の上端から出てくる藤の帯。下の辺を斜めに切り、写真とラクガキの絵を少し傾けて置く
    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            artwork
                .padding(.bottom, AppSpacing.large)

            Text(AuthStrings.welcomeGreeting)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(AppColors.onAccent)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, 5)
                .background(AppColors.yellow, in: Capsule())
                .rotationEffect(.degrees(-5))

            Text(AuthStrings.welcomeBrand)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(AuthStrings.welcomeDetail)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColors.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xLarge)
        .padding(.top, AppSpacing.section)
        .padding(.bottom, 64)
        .background {
            // 上へ大きくはみ出させ、時計の帯の裏と、引っ張ったときの余白まで藤にする
            SlantedBottomShape(drop: 40)
                .fill(AppColors.fuji)
                .padding(.top, -800)
        }
    }

    // 「撮って、描いて、その場所に残す」をそのまま絵にする：写真の枠、朱のラクガキ、黄のピン
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .frame(width: 112, height: 132)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppColors.sky)
                        .frame(width: 96, height: 92)
                        .overlay(alignment: .bottom) {
                            Image(systemName: "mountain.2.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .padding(.bottom, 6)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .padding(.top, 8)
                }
                .shadow(color: AppColors.fujiEdge.opacity(0.45), radius: 10, y: 6)
                .rotationEffect(.degrees(-7))

            Image(systemName: "scribble.variable")
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(AppColors.shu)
                .rotationEffect(.degrees(6))
                .offset(x: 46, y: 22)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppColors.onAccent, AppColors.yellow)
                .rotationEffect(.degrees(8))
                .offset(x: 150, y: 84)
        }
        .frame(width: 200, height: 140, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.medium) {
            NavigationLink {
                SignUpScreen(service: service, onSignedIn: onSignedIn)
            } label: {
                Text(AuthStrings.signUp)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RakugakiPrimaryButtonStyle())
            .accessibilityIdentifier("auth.sign-up")

            NavigationLink {
                SignInScreen(service: service, onSignedIn: onSignedIn)
            } label: {
                Text(AuthStrings.signIn)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RakugakiSecondaryButtonStyle(kind: .tinted))
            .accessibilityIdentifier("auth.sign-in")

            HStack(spacing: AppSpacing.medium) {
                Rectangle().fill(AppColors.outline).frame(height: 1.5)
                Text(AuthStrings.otherMethods)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColors.muted)
                    .fixedSize()
                Rectangle().fill(AppColors.outline).frame(height: 1.5)
            }
            .padding(.vertical, AppSpacing.xSmall)

            googleButton
            appleButton

            if let providerError {
                Text(providerError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.shuEdge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("auth.provider-error")
            }

            NavigationLink {
                PasswordResetScreen(service: service)
            } label: {
                Text(AuthStrings.passwordReset)
                    .font(.footnote.weight(.bold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("auth.password-reset")
        }
        .padding(.horizontal, AppSpacing.xLarge)
        .padding(.bottom, AppSpacing.large)
    }

    private var googleButton: some View {
        Button {
            guard !providerBusy else { return }
            providerBusy = true
            providerError = nil
            Task {
                defer { providerBusy = false }
                do {
                    _ = try await service.signInWithGoogle()
                    onSignedIn()
                } catch let error as ASWebAuthenticationSessionError
                    where error.code == .canceledLogin {
                    // 利用者がブラウザを閉じた場合は元の選択画面に戻る。
                } catch {
                    providerError = "Googleログインを完了できませんでした。設定と通信状態を確認してください。"
                }
            }
        } label: {
            HStack(spacing: AppSpacing.small) {
                Text(verbatim: "G")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("Googleで続ける")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RakugakiSecondaryButtonStyle(kind: .outlined))
        .disabled(providerBusy)
        .accessibilityIdentifier("auth.google")
    }

    private var appleButton: some View {
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
            case .failure(let error):
                appleNonce = ""
                if (error as? ASAuthorizationError)?.code != .canceled {
                    providerError = "Appleログインを完了できませんでした。"
                }
            }
        })
        // Appleの決まりに沿って標準のボタンを使い、形と高さだけほかのボタンにそろえる
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 49)
        .clipShape(Capsule())
        .disabled(providerBusy)
        .accessibilityIdentifier("auth.apple")
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
