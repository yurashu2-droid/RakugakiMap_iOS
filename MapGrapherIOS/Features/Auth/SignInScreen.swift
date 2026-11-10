import SwiftUI

@MainActor
struct SignInScreen: View {
    let service: any AuthUIService
    let onSignedIn: @MainActor () -> Void

    @StateObject private var model: AuthFlowModel
    @State private var email = ""
    @State private var password = ""

    init(
        service: any AuthUIService = FakeAuthUIService(),
        onSignedIn: @escaping @MainActor () -> Void = {}
    ) {
        self.service = service
        self.onSignedIn = onSignedIn
        _model = StateObject(wrappedValue: AuthFlowModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                Text(AuthStrings.signInTitle)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.ink)

                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    TextField(AuthStrings.email, text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth.email")
                        .accessibilityLabel(Text(AuthStrings.email))
                        .rakugakiField()

                    SecureField(AuthStrings.password, text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("auth.password")
                        .accessibilityLabel(Text(AuthStrings.password))
                        .rakugakiField()
                }

                PrimaryButton(isLoading: model.isSubmitting) {
                    Task { @MainActor in
                        if await model.signIn(email: email, password: password) {
                            onSignedIn()
                        }
                    }
                } label: {
                    Text(AuthStrings.submit)
                }
                .accessibilityIdentifier("auth.submit")

                AuthFeedbackView(state: model.state) {
                    Task { @MainActor in
                        if await model.signIn(email: email, password: password) {
                            onSignedIn()
                        }
                    }
                }

                VStack(spacing: AppSpacing.small) {
                    NavigationLink {
                        PasswordResetScreen(service: service)
                    } label: {
                        Text(AuthStrings.passwordReset)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("auth.password-reset")

                    NavigationLink {
                        SignUpScreen(service: service, onSignedIn: onSignedIn)
                    } label: {
                        Text(AuthStrings.signUp)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("auth.sign-up")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.auth.sign-in")
        .accessibilityLabel(Text(AuthStrings.signInTitle))
    }
}
