import SwiftUI

@MainActor
struct WelcomeScreen: View {
    let service: any AuthUIService
    let onSignedIn: @MainActor () -> Void

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
}
