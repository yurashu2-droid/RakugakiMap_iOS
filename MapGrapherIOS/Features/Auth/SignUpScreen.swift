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
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColors.ink)

                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    TextField(AuthStrings.displayName, text: $displayName)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.display-name")
                        .accessibilityLabel(Text(AuthStrings.displayName))

                    TextField(AuthStrings.email, text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.email")
                        .accessibilityLabel(Text(AuthStrings.email))

                    SecureField(AuthStrings.password, text: $password)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.password")
                        .accessibilityLabel(Text(AuthStrings.password))

                    SecureField(AuthStrings.passwordConfirmation, text: $passwordConfirmation)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.password-confirmation")
                        .accessibilityLabel(Text(AuthStrings.passwordConfirmation))
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
        .navigationTitle(AuthStrings.signUpTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.auth.sign-up")
        .accessibilityLabel(Text(AuthStrings.signUpTitle))
    }
}
