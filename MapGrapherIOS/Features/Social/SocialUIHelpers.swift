import SwiftUI
import MapGrapherCore

enum SocialUIMessage {
    static func errorKey(for error: Error?) -> LocalizedStringKey {
        guard let error = error as? SocialUIError else {
            return "social.error"
        }

        switch error {
        case .offline:
            return "social.error.offline"
        case .permissionDenied:
            return "social.error.permission"
        case .notFound:
            return "social.error.not-found"
        case .invalidInput:
            return "social.error.invalid-input"
        case .serviceUnavailable, .operationFailed:
            return "social.error"
        }
    }
}

@MainActor
struct SocialPrototypeNotice: View {
    let dataMode: SocialUIDataMode

    var body: some View {
        Group {
            if dataMode == .fake {
                PrototypeNotice(message: AppStrings.socialFakeNotice)
                    .accessibilityIdentifier("social.notice.fake")
            }
        }
    }
}

@MainActor
struct SocialActionError: View {
    let error: Error?

    var body: some View {
        Group {
            if error != nil {
                Label {
                    Text(SocialUIMessage.errorKey(for: error))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.red)
                .accessibilityIdentifier("social.action.error")
            }
        }
    }
}

@MainActor
struct SocialActionNotice: View {
    let dataMode: SocialUIDataMode

    var body: some View {
        Group {
            if dataMode == .fake {
                Text(AppStrings.socialFakeNotice)
                    .font(.subheadline)
                    .accessibilityIdentifier("social.notice.fake")
            } else {
                Text(AppStrings.socialOperationSuccess)
                    .font(.subheadline)
                    .accessibilityIdentifier("social.operation.success")
            }
        }
    }
}

extension ApprovalStatus {
    var isPendingStatus: Bool {
        if case .pending = self { return true }
        return false
    }

    var isApprovedStatus: Bool {
        if case .approved = self { return true }
        return false
    }

    var isRejectedStatus: Bool {
        if case .rejected = self { return true }
        return false
    }

    var displayKey: LocalizedStringKey {
        switch self {
        case .pending:
            "history.pending"
        case .approved:
            "history.approved"
        case .rejected:
            "history.rejected"
        }
    }
}
