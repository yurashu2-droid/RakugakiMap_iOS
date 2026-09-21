import SwiftUI
import MapGrapherCore

@MainActor
struct ProfileScreen: View {
    private let service: any SocialProfileUIService
    private let arRepository: (any ARExperienceServing)?
    private let sessionContext: SessionContext?
    private let assetLoader: PrivateAssetLoader?
    @StateObject private var model: ProfileScreenModel

    init(service: any SocialProfileUIService = FakeSocialProfileUIService(),
         arRepository: (any ARExperienceServing)? = nil,
         sessionContext: SessionContext? = nil,
         assetLoader: PrivateAssetLoader? = nil) {
        self.service = service
        self.arRepository = arRepository
        self.sessionContext = sessionContext
        self.assetLoader = assetLoader
        _model = StateObject(wrappedValue: ProfileScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            LoadStateView(
                state: model.state,
                emptyMessage: "profile.empty",
                errorMessage: SocialUIMessage.errorKey(for: model.error),
                retry: reload
            ) {
                profileContent
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.profile)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profile")
        .accessibilityLabel(Text(AppStrings.profile))
    }

    private var profileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                SocialPrototypeNotice(dataMode: service.dataMode)

                if let profile = model.profile {
                    profileCard(profile)
                    StampCardView(stats: model.stampStats)
                    navigationLinks
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func profileCard(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(AppStrings.profileDisplayName)
                        .font(.subheadline.weight(.semibold))
                    Text(profile.displayName)
                        .font(.title3.weight(.bold))
                }
            } icon: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppColors.coral)
            }
            .accessibilityIdentifier("profile.display-name")

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(AppStrings.profileUniqueID)
                    .font(.subheadline.weight(.semibold))
                Text(profile.userUniqueID)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("profile.unique-id")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
        }
    }

    private var navigationLinks: some View {
        VStack(spacing: AppSpacing.small) {
            NavigationLink {
                ProfileEditScreen(service: service)
            } label: {
                Label(AppStrings.profileEdit, systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("profile.edit")

            NavigationLink {
                FriendsScreen(service: service)
            } label: {
                Label(AppStrings.profileFriends, systemImage: "person.2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("profile.friends")

            NavigationLink {
                FriendRequestScreen(service: service)
            } label: {
                Label(AppStrings.profileFriendRequests, systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("profile.friend-requests")

            NavigationLink {
                HistoryScreen(service: service, arRepository: arRepository,
                              sessionContext: sessionContext, assetLoader: assetLoader)
            } label: {
                Label(AppStrings.profileHistory, systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("profile.history")

            NavigationLink {
                AlbumListScreen(service: service)
            } label: {
                Label(AppStrings.profileAlbums, systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("profile.albums")
        }
        .font(.headline)
        .buttonStyle(.bordered)
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }
}
