import SwiftUI
import MapGrapherCore
import UIKit

@MainActor
struct GroupDetailScreen: View {
    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private let postingService: any PostingUIService
    private let assetLoader: PrivateAssetLoader?
    private let isUITesting: Bool
    @StateObject private var model: GroupDetailScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsPosting = false
    @State private var showsPrompt = false
    @State private var showsSettings = false
    @State private var showsLeaveConfirmation = false

    init(summary: GroupSummary, service: any GroupsServing, context: SessionContext?,
         dataMode: GroupUIDataMode, postingService: any PostingUIService,
         assetLoader: PrivateAssetLoader? = nil, isUITesting: Bool) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
        self.postingService = postingService
        self.assetLoader = assetLoader
        self.isUITesting = isUITesting
        _model = StateObject(wrappedValue: GroupDetailScreenModel(
            summary: summary, service: service, context: context, dataMode: dataMode
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                GroupPrototypeNotice(dataMode: dataMode)
                LoadStateView(state: model.state, emptyMessage: "groups.empty",
                              errorMessage: GroupUIMessage.errorKey(for: model.error),
                              retry: { Task { await model.load() } }) {
                    detailContent
                }
                if model.didCompleteAction { GroupActionNotice(dataMode: dataMode) }
                if let error = model.error, model.state != .error {
                    Text(GroupUIMessage.errorKey(for: error))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("groups.action.error")
                }
            }
            .padding(AppSpacing.large)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationTitle(model.summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model.summary.isOwner {
                        Button("groups.settings", systemImage: "gearshape") {
                            showsSettings = true
                        }
                    } else {
                        Button("groups.leave", systemImage: "rectangle.portrait.and.arrow.right",
                               role: .destructive) {
                            showsLeaveConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("groups.menu"))
                }
                .accessibilityIdentifier("group.menu")
            }
        }
        .task { await model.load() }
        .onChange(of: model.didExitGroup) { _, didExit in
            if didExit { dismiss() }
        }
        .sheet(isPresented: $showsPosting, onDismiss: {
            Task { await model.load() }
        }) {
            PostingFlowScreen(isUITesting: isUITesting, service: postingService,
                              missionID: model.summary.missionID)
        }
        .sheet(isPresented: $showsPrompt, onDismiss: {
            Task { await model.load() }
        }) {
            if let missionID = model.summary.missionID {
                MissionPromptScreen(missionID: missionID, service: service, context: context,
                                    dataMode: dataMode)
            }
        }
        .sheet(isPresented: $showsSettings, onDismiss: {
            Task { await model.load() }
        }) {
            GroupSettingsScreen(model: model, dataMode: dataMode)
        }
        .confirmationDialog("groups.leave.confirm", isPresented: $showsLeaveConfirmation) {
            Button("groups.leave", role: .destructive) {
                let groupID = model.summary.id
                Task {
                    await model.perform({ service, context in
                        try await service.leave(groupID: groupID, context: context)
                    }, exitsGroup: true)
                    if model.didExitGroup { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen.group-detail")
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if !model.summary.description.isEmpty {
                Text(model.summary.description)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.75))
            }
            missionSection
            participantSection
            memberSection
        }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("groups.mission.title").font(.headline)
            if let date = model.summary.missionDate {
                Text(date).font(.caption).foregroundStyle(.secondary)
            }
            if let status = model.summary.missionStatus {
                Text(status.displayKey)
                    .font(.subheadline.weight(.semibold))
            }
            if let prompt = model.summary.promptText, !prompt.isEmpty {
                Text(prompt).font(.title3.weight(.semibold))
            } else {
                Text("groups.mission.no-prompt").foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text("groups.answer.count")
                Text("\(model.summary.answeredCount)/\(model.summary.participantCount)")
            }
            .font(.caption)
            if model.isTodayIneligible {
                Text("groups.mission.join-tomorrow")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.canSetPrompt {
                Button("groups.mission.set-prompt") { showsPrompt = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("group.mission.set-prompt")
            }
            if model.canAnswer {
                Button("groups.mission.answer") { showsPosting = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("group.mission.answer")
            } else if model.myParticipant?.answered == true,
                      let missionID = model.summary.missionID {
                Text("groups.mission.answered").font(.subheadline)
                Button("groups.mission.withdraw", role: .destructive) {
                    Task {
                        await model.perform { service, context in
                            try await service.withdrawAnswer(missionID: missionID, context: context)
                        }
                    }
                }
                .disabled(model.isWorking)
            }
            if model.summary.isOwner, model.summary.missionStatus == .awaitingPrompt,
               let missionID = model.summary.missionID {
                Button("groups.mission.reassign") {
                    Task {
                        await model.perform { service, context in
                            _ = try await service.reassignSetter(missionID: missionID,
                                                                 context: context)
                        }
                    }
                }
                .disabled(model.isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.paper.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var participantSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("groups.participants").font(.headline)
            if model.participants.isEmpty {
                Text("groups.participants.empty").foregroundStyle(.secondary)
            }
            ForEach(model.participants, id: \.participantID) { participant in
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack {
                        Text(participant.participantName)
                        Spacer()
                        Text(participant.answered ? "groups.mission.answered" :
                                "groups.mission.not-answered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if participant.answered {
                        if let asset = participant.latestApprovedRakugakiAsset
                            ?? participant.photoAsset {
                            GroupAnswerThumbnail(asset: asset, assetLoader: assetLoader,
                                                 context: context)
                        } else {
                            Text("groups.answer.image-unavailable")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.small)
            }
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("groups.members").font(.headline)
            ForEach(model.members, id: \.id) { member in
                HStack {
                    VStack(alignment: .leading) {
                        Text(member.displayName)
                        Text(member.userUniqueID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(member.role.displayKey).font(.caption)
                }
                .padding(.vertical, AppSpacing.small)
            }
        }
    }
}

@MainActor
private struct GroupAnswerThumbnail: View {
    let asset: AssetReference
    let assetLoader: PrivateAssetLoader?
    let context: SessionContext?
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if unavailable {
                Text("groups.answer.image-unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: asset.path) {
            guard let assetLoader, let context else {
                unavailable = true
                return
            }
            do {
                let result = try await assetLoader.load(
                    asset: asset, targetPixelSize: CGSize(width: 720, height: 400),
                    context: context
                )
                guard !Task.isCancelled else { return }
                image = result
            } catch {
                guard !Task.isCancelled else { return }
                unavailable = true
            }
        }
    }
}
