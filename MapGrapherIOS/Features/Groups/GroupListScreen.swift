import SwiftUI
import MapGrapherCore

@MainActor
struct GroupListScreen: View {
    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private let postingService: any PostingUIService
    private let assetLoader: PrivateAssetLoader?
    private let isUITesting: Bool
    @StateObject private var model: GroupListScreenModel
    @State private var showsCreateSheet = false

    init(
        service: any GroupsServing = FakeGroupsServing(),
        context: SessionContext? = nil,
        dataMode: GroupUIDataMode = .fake,
        postingService: any PostingUIService = FakePostingUIService(),
        assetLoader: PrivateAssetLoader? = nil,
        isUITesting: Bool = false
    ) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
        self.postingService = postingService
        self.assetLoader = assetLoader
        self.isUITesting = isUITesting
        _model = StateObject(wrappedValue: GroupListScreenModel(
            service: service, context: context, dataMode: dataMode
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    GroupPrototypeNotice(dataMode: dataMode)

                    Button {
                        model.clearActionNotice()
                        showsCreateSheet = true
                    } label: {
                        Label("groups.create", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("groups.create")

                    invitationSection

                    LoadStateView(
                        state: model.state,
                        emptyMessage: "groups.empty",
                        errorMessage: GroupUIMessage.errorKey(for: model.error),
                        retry: reload
                    ) {
                        groupList
                    }

                    if model.didCompleteAction {
                        GroupActionNotice(dataMode: dataMode)
                    }
                    if model.error != nil {
                        Text(GroupUIMessage.errorKey(for: model.error))
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("groups.action.error")
                    }
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.medium)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.groups)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
            }
            .sheet(isPresented: $showsCreateSheet) {
                GroupCreateScreen(service: service, context: context, dataMode: dataMode) {
                    showsCreateSheet = false
                    Task { await model.load() }
                    model.clearActionNotice()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.groups")
        .accessibilityLabel(Text(AppStrings.groups))
    }

    @ViewBuilder
    private var invitationSection: some View {
        if !model.invitations.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("groups.invitation.title")
                    .font(.headline)
                ForEach(model.invitations) { invitation in
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(invitation.groupName)
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text(invitation.inviterName)
                            Text("groups.invitation.from-label")
                        }
                        .font(.subheadline)
                        HStack(spacing: 4) {
                            Text("groups.invitation.expires-label")
                            Text(invitation.expiresAt, style: .date)
                        }
                        .font(.caption)
                        .foregroundStyle(AppColors.ink.opacity(0.70))
                        HStack(spacing: AppSpacing.small) {
                            Button("groups.invitation.accept") {
                                Task { await model.respond(to: invitation, accepted: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("group-invitation.accept.\(invitation.id.uuidString)")
                            Button("groups.invitation.decline", role: .destructive) {
                                Task { await model.respond(to: invitation, accepted: false) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("group-invitation.decline.\(invitation.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.medium)
                    .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityIdentifier("group-invitation.row.\(invitation.id.uuidString)")
                }
            }
        }
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ForEach(model.groups) { summary in
                NavigationLink {
                    GroupDetailScreen(
                        summary: summary,
                        service: service,
                        context: context,
                        dataMode: dataMode,
                        postingService: postingService,
                        assetLoader: assetLoader,
                        isUITesting: isUITesting
                    )
                } label: {
                    GroupSummaryCard(summary: summary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("group.row.\(summary.id.uuidString)")
            }
        }
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }
}

@MainActor
private struct GroupCreateScreen: View {
    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GroupCreateScreenModel
    @State private var name = ""
    @State private var description = ""

    init(
        service: any GroupsServing,
        context: SessionContext?,
        dataMode: GroupUIDataMode,
        onCreated: @escaping () -> Void
    ) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
        self.onCreated = onCreated
        _model = StateObject(wrappedValue: GroupCreateScreenModel(
            service: service, context: context, dataMode: dataMode
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GroupPrototypeNotice(dataMode: dataMode)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("groups.name.placeholder", text: $name)
                        .accessibilityIdentifier("groups.create.name")
                    TextField("groups.description.placeholder", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("groups.create.description")
                } header: {
                    Text("groups.create.title")
                }
                Section {
                    Button {
                        Task {
                            if await model.create(name: name, description: description) {
                                onCreated()
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 48)
                        } else {
                            Text("groups.save")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("groups.create.save")
                }
                if let error = model.error {
                    Text(GroupUIMessage.errorKey(for: error))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("groups.action.error")
                }
            }
            .navigationTitle("groups.create.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("posting.close.cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen.group-create")
    }
}

@MainActor
private struct GroupSummaryCard: View {
    let summary: GroupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name)
                    .font(.headline)
                Spacer()
                Text(summary.isOwner ? "groups.owner" : "groups.member")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.coral)
            }
            if !summary.description.isEmpty {
                Text(summary.description)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: AppSpacing.medium) {
                Label("\(summary.memberCount)人", systemImage: "person.2")
                if let missionDate = summary.missionDate {
                    Label(missionDate, systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(AppColors.ink.opacity(0.70))

            if let missionStatus = summary.missionStatus {
                HStack(spacing: AppSpacing.small) {
                    Text(missionStatus.displayKey)
                        .font(.subheadline.weight(.semibold))
                    Text(missionDateDetail)
                        .font(.caption)
                }
            } else {
                Text("groups.mission.none")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.70))
            }
            if let prompt = summary.promptText, !prompt.isEmpty {
                Text(prompt)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                Text("groups.answer.count")
                Text("\(summary.answeredCount)/\(summary.participantCount)")
            }
            .font(.caption)
            .foregroundStyle(AppColors.ink.opacity(0.70))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
        }
    }

    private var missionDateDetail: LocalizedStringKey {
        guard let missionDate = summary.missionDate else { return "groups.mission.no-date" }
        switch GroupMissionDate.state(for: missionDate) {
        case .today:
            return summary.hasAnswered ? "groups.mission.answered" : "groups.mission.today"
        case .future:
            return "groups.mission.future"
        case .past:
            return "groups.mission.past"
        case .invalid:
            return "groups.mission.invalid-date"
        }
    }
}
