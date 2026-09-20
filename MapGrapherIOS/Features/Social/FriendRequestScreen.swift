import SwiftUI

@MainActor
struct FriendRequestScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: FriendsScreenModel

    init(service: any SocialProfileUIService = FakeSocialProfileUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: FriendsScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    SocialPrototypeNotice(dataMode: service.dataMode)

                    LoadStateView(
                        state: model.state,
                        emptyMessage: AppStrings.socialRequestsEmpty,
                        errorMessage: SocialUIMessage.errorKey(for: model.error),
                        retry: reload
                    ) {
                        requestList
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
            .navigationTitle(AppStrings.socialRequestsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.loadRequests()
            }
        }
        .accessibilityIdentifier("screen.friend-requests")
    }

    private var requestList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ForEach(model.requests) { request in
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(request.requesterName)
                            .font(.headline)
                        Text(request.requesterUniqueID)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(AppColors.ink.opacity(0.70))
                    }

                    HStack(spacing: AppSpacing.small) {
                        Button(AppStrings.socialAccept) {
                            Task { await model.respond(to: request, accepted: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("friend-request.accept.\(request.id.uuidString)")

                        Button(AppStrings.socialReject, role: .destructive) {
                            Task { await model.respond(to: request, accepted: false) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("friend-request.reject.\(request.id.uuidString)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.medium)
                .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                }
                .accessibilityIdentifier("friend-request.row.\(request.id.uuidString)")
            }
        }
    }

    private func reload() {
        Task { @MainActor in
            await model.loadRequests()
        }
    }
}
