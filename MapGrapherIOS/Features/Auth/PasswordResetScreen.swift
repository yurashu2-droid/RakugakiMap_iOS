import SwiftUI

@MainActor
struct PasswordResetScreen: View {
    let service: any AuthUIService

    @StateObject private var model: AuthFlowModel
    @State private var email = ""

    init(service: any AuthUIService = FakeAuthUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: AuthFlowModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                Text(AuthStrings.passwordResetTitle)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColors.ink)

                Text(AuthStrings.resetSentDetail)
                    .font(.body)
                    .foregroundStyle(AppColors.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                TextField(AuthStrings.email, text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("auth.email")
                    .accessibilityLabel(Text(AuthStrings.email))

                PrimaryButton(isLoading: model.isSubmitting) {
                    Task { @MainActor in
                        await model.sendPasswordReset(email: email)
                    }
                } label: {
                    Text(AuthStrings.submit)
                }
                .accessibilityIdentifier("auth.submit")

                AuthFeedbackView(state: model.state) {
                    Task { @MainActor in
                        await model.sendPasswordReset(email: email)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationTitle(AuthStrings.passwordResetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.auth.password-reset")
        .accessibilityLabel(Text(AuthStrings.passwordResetTitle))
    }
}
