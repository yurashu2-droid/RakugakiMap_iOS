import MapGrapherCore
import SwiftUI

@MainActor
struct SubmissionStatusScreen: View {
    let result: PostingSubmissionResult?
    let error: PostingFlowError?
    let isBusy: Bool
    let waitingForApproval: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                statusIcon

                VStack(spacing: AppSpacing.medium) {
                    Text(titleKey)
                        .font(.title.bold())
                        .foregroundStyle(AppColors.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(statusIdentifier)
                Text(detailKey)
                        .font(.body)
                        .foregroundStyle(AppColors.ink.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if waitingForApproval && isWaiting {
                    Text("posting.status.approval-waiting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.coral)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("posting.status.approval-waiting")
                }

                if let error {
                    PostingErrorView(error: error)
                }

                VStack(spacing: AppSpacing.medium) {
                    if canRetry {
                        Button {
                            onRetry()
                        } label: {
                            Label("posting.status.retry", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                        .accessibilityIdentifier("posting.status.retry")
                    }

                    Button("posting.status.edit", action: onBack)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("posting.status.edit")
                }

                Text("posting.status.draft-kept")
                    .font(.caption)
                    .foregroundStyle(AppColors.ink.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("posting.status.draft-kept")
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.xLarge)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.posting.status")
        .accessibilityLabel(Text(titleKey))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result?.state {
        case .some(.completed):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.mint)
                .accessibilityHidden(true)
        case .some(.needsLogin), .some(.needsCorrection):
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.coral)
                .accessibilityHidden(true)
        default:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.coral)
                .accessibilityHidden(true)
        }
    }

    private var canRetry: Bool {
        switch result?.state {
        case .some(.queued), .some(.retryWaiting), .some(.needsLogin), .some(.needsCorrection),
             .some(.outcomeUnknown), .some(.cancelled):
            true
        default:
            error != nil
        }
    }

    private var isWaiting: Bool {
        switch result?.state {
        case .some(.queued), .some(.uploading), .some(.registering):
            true
        default:
            false
        }
    }

    private var statusIdentifier: String {
        switch result?.state {
        case .some(.completed):
            "posting.status.success"
        case .some(.retryWaiting), .some(.outcomeUnknown):
            "posting.status.retry-waiting"
        case .some(.needsLogin):
            "posting.status.needs-login"
        case .some(.needsCorrection):
            "posting.status.needs-correction"
        default:
            "posting.status.waiting"
        }
    }

    private var titleKey: LocalizedStringKey {
        switch result?.state {
        case .some(.completed):
            "posting.status.success"
        case .some(.retryWaiting), .some(.outcomeUnknown):
            "posting.status.retry-waiting"
        case .some(.needsLogin):
            "posting.status.needs-login"
        case .some(.needsCorrection):
            "posting.status.needs-correction"
        default:
            "posting.status.waiting"
        }
    }

    private var detailKey: LocalizedStringKey {
        switch result?.state {
        case .some(.completed):
            "posting.status.success.detail"
        case .some(.retryWaiting), .some(.outcomeUnknown):
            "posting.status.retry-waiting.detail"
        case .some(.needsLogin):
            "posting.status.needs-login.detail"
        case .some(.needsCorrection):
            "posting.status.needs-correction.detail"
        default:
            "posting.status.waiting.detail"
        }
    }
}
