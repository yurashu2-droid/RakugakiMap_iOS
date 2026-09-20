import SwiftUI

@MainActor
struct HistoryScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: HistoryScreenModel

    init(service: any SocialProfileUIService = FakeSocialProfileUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: HistoryScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    SocialPrototypeNotice(dataMode: service.dataMode)
                    LoadStateView(
                        state: model.state,
                        emptyMessage: AppStrings.historyEmpty,
                        errorMessage: SocialUIMessage.errorKey(for: model.error),
                        retry: reload
                    ) {
                        historyList
                    }
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.medium)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.historyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
            }
        }
        .accessibilityIdentifier("screen.rakugaki-history")
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ForEach(model.items) { item in
                if item.canModerate {
                    NavigationLink {
                        ApprovalScreen(item: item, service: service)
                    } label: {
                        historyRow(item)
                    }
                    .accessibilityIdentifier("history.row.\(item.id.uuidString)")
                } else {
                    historyRow(item)
                        .accessibilityIdentifier("history.row.\(item.id.uuidString)")
                }
            }
        }
    }

    private func historyRow(_ item: RakugakiHistoryItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: item.status.isApprovedStatus ? "checkmark.circle.fill" : "scribble.variable")
                .font(.title2)
                .foregroundStyle(item.status.isRejectedStatus ? .red : AppColors.coral)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(item.photoTitle)
                    .font(.headline)
                Text(item.authorName)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.70))
                Text(item.status.displayKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.ink)
            }
            Spacer(minLength: AppSpacing.small)
            if item.canModerate && item.status.isPendingStatus {
                Image(systemName: "chevron.forward")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
        }
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }
}
