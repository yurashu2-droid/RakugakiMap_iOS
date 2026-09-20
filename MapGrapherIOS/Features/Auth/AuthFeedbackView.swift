import SwiftUI

@MainActor
struct AuthFeedbackView: View {
    let state: AuthViewState
    let onRetry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle, .submitting:
            EmptyView()
        case .confirmationRequired(let email):
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Label(AuthStrings.confirmationTitle, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppColors.ink)
                Text(AuthStrings.confirmationDetail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.78))
                Text(email)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.coral)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.mint.opacity(0.24), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("auth.confirmation")
        case .passwordResetSent(let email):
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Label(AuthStrings.resetSentTitle, systemImage: "envelope.badge.fill")
                    .font(.headline)
                    .foregroundStyle(AppColors.ink)
                Text(AuthStrings.resetSentDetail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.78))
                Text(email)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.coral)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.mint.opacity(0.24), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("auth.reset-sent")
        case .failed(let error):
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Label(error.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(AuthStrings.retry, action: onRetry)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("auth.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("auth.error")
        }
    }
}
