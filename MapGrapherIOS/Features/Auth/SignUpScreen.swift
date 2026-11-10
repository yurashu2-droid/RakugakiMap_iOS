import SwiftUI

@MainActor
struct SignUpScreen: View {
    let service: any AuthUIService
    let onSignedIn: @MainActor () -> Void

    @StateObject private var model: AuthFlowModel
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""

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
                Text(AuthStrings.signUpTitle)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.ink)

                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    TextField(AuthStrings.displayName, text: $displayName)
                        .textContentType(.name)
                        .accessibilityIdentifier("auth.display-name")
                        .accessibilityLabel(Text(AuthStrings.displayName))
                        .rakugakiField()

                    TextField(AuthStrings.email, text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth.email")
                        .accessibilityLabel(Text(AuthStrings.email))
                        .rakugakiField()

                    SecureField(AuthStrings.password, text: $password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("auth.password")
                        .accessibilityLabel(Text(AuthStrings.password))
                        .rakugakiField()

                    SecureField(AuthStrings.passwordConfirmation, text: $passwordConfirmation)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("auth.password-confirmation")
                        .accessibilityLabel(Text(AuthStrings.passwordConfirmation))
                        .rakugakiField()
                }

                PrimaryButton(isLoading: model.isSubmitting) {
                    Task { @MainActor in
                        if await model.signUp(
                            email: email,
                            displayName: displayName,
                            password: password,
                            confirmation: passwordConfirmation
                        ) {
                            onSignedIn()
                        }
                    }
                } label: {
                    Text(AuthStrings.submit)
                }
                .accessibilityIdentifier("auth.submit")

                AuthFeedbackView(state: model.state) {
                    Task { @MainActor in
                        if await model.signUp(
                            email: email,
                            displayName: displayName,
                            password: password,
                            confirmation: passwordConfirmation
                        ) {
                            onSignedIn()
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.auth.sign-up")
        .accessibilityLabel(Text(AuthStrings.signUpTitle))
    }
}
