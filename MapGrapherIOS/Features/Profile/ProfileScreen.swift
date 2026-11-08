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

    // 案A：顔はホームと同じ黄色いふち。名前とIDを真ん中にそろえる
    private func profileCard(_ profile: UserProfile) -> some View {
        VStack(spacing: AppSpacing.small) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(AppColors.fuji)
                .frame(width: 100, height: 100)
                .background(AppColors.fujiTint, in: Circle())
                .overlay { Circle().stroke(AppColors.yellow, lineWidth: 4) }
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.xSmall) {
                Text(AppStrings.profileDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.muted)
                Text(profile.displayName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(AppColors.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.display-name")

            Text("profile.unique-id.value \(profile.userUniqueID)")
                .font(.subheadline.monospaced())
                .foregroundStyle(AppColors.muted)
                .textSelection(.enabled)
                .accessibilityLabel(Text(AppStrings.profileUniqueID) + Text(verbatim: " \(profile.userUniqueID)"))
                .accessibilityIdentifier("profile.unique-id")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xLarge)
        .padding(.horizontal, AppSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.surface)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }

    // 案A：箱に入れず、色の丸い絵と文字の行を地に直接並べる。行の間に細い線
    private var navigationLinks: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ProfileEditScreen(service: service)
            } label: {
                ProfileRow(title: AppStrings.profileEdit, symbol: "pencil",
                           tint: AppColors.fujiTint, iconColor: AppColors.fujiEdge)
            }
            .accessibilityIdentifier("profile.edit")

            NavigationLink {
                FriendsScreen(service: service)
            } label: {
                ProfileRow(title: AppStrings.profileFriends, symbol: "person.2.fill",
                           tint: AppColors.limeTint, iconColor: AppColors.onAccent)
            }
            .accessibilityIdentifier("profile.friends")

            NavigationLink {
                FriendRequestScreen(service: service)
            } label: {
                ProfileRow(title: AppStrings.profileFriendRequests, symbol: "person.badge.plus",
                           tint: AppColors.skyTint, iconColor: AppColors.onAccent)
            }
            .accessibilityIdentifier("profile.friend-requests")

            NavigationLink {
                HistoryScreen(service: service, arRepository: arRepository,
                              sessionContext: sessionContext, assetLoader: assetLoader)
            } label: {
                ProfileRow(title: AppStrings.profileHistory, symbol: "clock.arrow.circlepath",
                           tint: AppColors.shuTint, iconColor: AppColors.shuEdge)
            }
            .accessibilityIdentifier("profile.history")

            NavigationLink {
                AlbumListScreen(service: service)
            } label: {
                ProfileRow(title: AppStrings.profileAlbums, symbol: "rectangle.stack.fill",
                           tint: AppColors.yellowTint, iconColor: AppColors.onAccent, showsDivider: false)
            }
            .accessibilityIdentifier("profile.albums")
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }
}

/// マイページの1行。左に色の丸い絵、右に矢印。下に細い線
private struct ProfileRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let iconColor: Color
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(tint, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColors.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 60)
            if showsDivider {
                Rectangle()
                    .fill(AppColors.outline)
                    .frame(height: 1)
                    .padding(.leading, 48)
            }
        }
        .contentShape(Rectangle())
    }
}
