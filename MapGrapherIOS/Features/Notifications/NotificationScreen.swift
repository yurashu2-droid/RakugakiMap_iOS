import SwiftUI
import MapGrapherCore

@MainActor
struct NotificationScreen: View {
    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private let postingService: any PostingUIService
    private let assetLoader: PrivateAssetLoader?
    private let isUITesting: Bool
    @StateObject private var model: NotificationScreenModel
    @State private var selectedGroupID: UUID?

    init(service: any GroupsServing = FakeGroupsServing(),
         context: SessionContext? = nil,
         dataMode: GroupUIDataMode = .fake,
         postingService: any PostingUIService = FakePostingUIService(),
         assetLoader: PrivateAssetLoader? = nil,
         isUITesting: Bool = false) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
        self.postingService = postingService
        self.assetLoader = assetLoader
        self.isUITesting = isUITesting
        _model = StateObject(wrappedValue: NotificationScreenModel(
            service: service, context: context, dataMode: dataMode
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    GroupPrototypeNotice(dataMode: dataMode)
                    if model.targetUnavailable {
                        ContentUnavailableView("notifications.target.unavailable",
                                               systemImage: "link.badge.plus",
                                               description: Text("notifications.target.description"))
                            .accessibilityIdentifier("notifications.target.unavailable")
                    }
                    LoadStateView(state: model.state,
                                  emptyMessage: "notifications.empty",
                                  errorMessage: GroupUIMessage.errorKey(for: model.error),
                                  retry: { Task { await model.load() } }) {
                        VStack(spacing: AppSpacing.small) {
                            ForEach(model.rows, id: \.id) { item in
                                Button {
                                    Task {
                                        selectedGroupID = await model.markRead(item)?.id
                                    }
                                } label: {
                                    notificationRow(item)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isWorking)
                                .accessibilityIdentifier("notification.row.\(item.id.uuidString)")
                            }
                        }
                    }
                    if let error = model.error, model.state != .error {
                        Text(GroupUIMessage.errorKey(for: error))
                            .foregroundStyle(.red)
                    }
                }
                .padding(AppSpacing.large)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.notifications)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .navigationDestination(item: $selectedGroupID) { groupID in
                if let summary = model.summaries.first(where: { $0.id == groupID }) {
                    GroupDetailScreen(summary: summary, service: service, context: context,
                                      dataMode: dataMode, postingService: postingService,
                                      assetLoader: assetLoader,
                                      isUITesting: isUITesting)
                } else {
                    Text("notifications.target.unavailable")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.notifications")
        .accessibilityLabel(Text(AppStrings.notifications))
    }

    private func notificationRow(_ item: GroupNotification) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: item.readAt == nil ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(item.readAt == nil ? AppColors.coral : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(GroupNotificationMessage.eventKey(item.eventType))
                    .font(.headline)
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.paper.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
        }
    }
}
