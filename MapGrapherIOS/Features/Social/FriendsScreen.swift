import SwiftUI

@MainActor
struct FriendsScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: FriendsScreenModel
    @State private var uniqueID = ""
    @State private var friendToRemove: FriendRelation?
    @State private var showsRemoveConfirmation = false

    init(service: any SocialProfileUIService = FakeSocialProfileUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: FriendsScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    SocialPrototypeNotice(dataMode: service.dataMode)
                    addFriendSection

                    NavigationLink {
                        FriendRequestScreen(service: service)
                    } label: {
                        Label {
                            Text(AppStrings.socialFriendsPending)
                        } icon: {
                            Image(systemName: "person.badge.clock")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("friends.pending")

                    LoadStateView(
                        state: model.state,
                        emptyMessage: AppStrings.socialFriendsEmpty,
                        errorMessage: SocialUIMessage.errorKey(for: model.error),
                        retry: reload
                    ) {
                        friendsList
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
            .navigationTitle(AppStrings.socialFriendsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.loadFriends()
            }
            .confirmationDialog(
                AppStrings.socialFriendsRemoveConfirm,
                isPresented: $showsRemoveConfirmation
            ) {
                Button(AppStrings.socialFriendsRemove, role: .destructive) {
                    guard let friend = friendToRemove else { return }
                    Task { await model.remove(friend: friend) }
                }
                Button("posting.close.cancel", role: .cancel) {}
            }
        }
        .accessibilityIdentifier("screen.friends")
    }

    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(AppStrings.socialFriendsAdd)
                .font(.headline)
            HStack(spacing: AppSpacing.small) {
                TextField(AppStrings.socialFriendsUniqueIDPlaceholder, text: $uniqueID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("friends.unique-id")

                Button {
                    Task {
                        await model.requestFriend(uniqueID: uniqueID)
                        if model.error == nil {
                            uniqueID = ""
                        }
                    }
                } label: {
                    Label(AppStrings.socialFriendsRequest, systemImage: "paperplane")
                        .labelStyle(.iconOnly)
                }
                .frame(width: 48, height: 48)
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking || uniqueID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(AppStrings.socialFriendsRequest)
                .accessibilityIdentifier("friends.request")
            }
        }
    }

    private var friendsList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ForEach(model.friends) { friend in
                HStack(alignment: .center, spacing: AppSpacing.medium) {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(friend.friendName)
                            .font(.headline)
                        Text(friend.friendUniqueID)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(AppColors.ink.opacity(0.70))
                    }
                    Spacer(minLength: AppSpacing.small)
                    Button {
                        friendToRemove = friend
                        showsRemoveConfirmation = true
                    } label: {
                        Image(systemName: "person.badge.minus")
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(AppStrings.socialFriendsRemove)
                    .accessibilityIdentifier("friend.remove.\(friend.id.uuidString)")
                }
                .padding(AppSpacing.medium)
                .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                }
                .accessibilityIdentifier("friend.row.\(friend.id.uuidString)")
            }
        }
    }

    private func reload() {
        Task { @MainActor in
            await model.loadFriends()
        }
    }
}
