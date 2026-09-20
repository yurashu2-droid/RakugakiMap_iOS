import SwiftUI

@MainActor
struct ApprovalScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: ApprovalScreenModel

    init(
        item: RakugakiHistoryItem,
        service: any SocialProfileUIService = FakeSocialProfileUIService()
    ) {
        self.service = service
        _model = StateObject(wrappedValue: ApprovalScreenModel(item: item, service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                SocialPrototypeNotice(dataMode: service.dataMode)

                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Text(model.item.photoTitle)
                        .font(.title2.weight(.bold))
                    Text(model.item.authorName)
                        .font(.body)
                        .foregroundStyle(AppColors.ink.opacity(0.72))
                    Text(AppStrings.historyApprovalDetail)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(model.item.status.displayKey, systemImage: "flag")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.large)
                .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                }
                .accessibilityIdentifier("history.approval.detail")

                if model.item.canModerate && model.item.status.isPendingStatus {
                    HStack(spacing: AppSpacing.medium) {
                        Button(AppStrings.historyApprove) {
                            Task { await model.setApproval(true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("history.approve")

                        Button(AppStrings.historyReject, role: .destructive) {
                            Task { await model.setApproval(false) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("history.reject")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(AppStrings.historyConfirm)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.didCompleteAction {
                    SocialActionNotice(dataMode: service.dataMode)
                }
                SocialActionError(error: model.error)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationTitle(AppStrings.historyApprovalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.rakugaki-approval")
    }
}
