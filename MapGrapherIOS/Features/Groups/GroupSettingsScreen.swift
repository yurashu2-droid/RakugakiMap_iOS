import SwiftUI
import MapGrapherCore

@MainActor
struct GroupSettingsScreen: View {
    @ObservedObject var model: GroupDetailScreenModel
    let dataMode: GroupUIDataMode
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var friendID = ""
    @State private var memberToRemove: UUID?
    @State private var memberToTransfer: UUID?
    @State private var showsArchiveConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GroupPrototypeNotice(dataMode: dataMode)
                }
                Section("groups.settings.edit") {
                    TextField("groups.name.placeholder", text: $name)
                        .accessibilityIdentifier("group.settings.name")
                    TextField("groups.description.placeholder", text: $description,
                              axis: .vertical)
                        .lineLimit(3...6)
                    Button("groups.save") {
                        let groupID = model.summary.id
                        let editedName = name
                        let editedDescription = description
                        Task {
                            await model.perform { service, context in
                                _ = try await service.updateGroup(id: groupID, name: editedName,
                                                                  description: editedDescription,
                                                                  context: context)
                            }
                        }
                    }
                    .disabled(model.isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("group.settings.save")
                }
                Section("groups.invite.title") {
                    TextField("groups.invite.id", text: $friendID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("group.invite.id")
                    Button("groups.invite.send") {
                        Task {
                            if await model.invite(uniqueID: friendID) { friendID = "" }
                        }
                    }
                    .disabled(model.isWorking || friendID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("group.invite.send")
                    if let invitation = model.recentInvitation, invitation.status == .pending {
                        Text("groups.invite.pending")
                        Button("groups.invite.cancel", role: .destructive) {
                            Task { await model.cancelRecentInvitation() }
                        }
                        .disabled(model.isWorking)
                    }
                }
                Section("groups.members") {
                    ForEach(model.members.filter { $0.status == .active && $0.id != model.summary.ownerID },
                            id: \.id) { member in
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(member.displayName)
                            HStack {
                                Button("groups.member.remove", role: .destructive) {
                                    memberToRemove = member.id
                                }
                                Button("groups.member.transfer") {
                                    memberToTransfer = member.id
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                Section {
                    Button("groups.archive", role: .destructive) {
                        showsArchiveConfirmation = true
                    }
                } footer: {
                    Text("groups.owner.cannot-leave")
                }
                if model.didCompleteAction {
                    Section { GroupActionNotice(dataMode: dataMode) }
                }
                if let error = model.error {
                    Section {
                        Text(GroupUIMessage.errorKey(for: error)).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("groups.settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("posting.close.cancel") { dismiss() }
                }
            }
            .onAppear {
                name = model.summary.name
                description = model.summary.description
            }
            .confirmationDialog("groups.member.remove.confirm",
                                isPresented: Binding(get: { memberToRemove != nil },
                                                     set: { if !$0 { memberToRemove = nil } })) {
                Button("groups.member.remove", role: .destructive) {
                    guard let memberID = memberToRemove else { return }
                    let groupID = model.summary.id
                    memberToRemove = nil
                    Task {
                        await model.perform { service, context in
                            try await service.removeMember(groupID: groupID,
                                                           memberID: memberID, context: context)
                        }
                    }
                }
            }
            .confirmationDialog("groups.member.transfer.confirm",
                                isPresented: Binding(get: { memberToTransfer != nil },
                                                     set: { if !$0 { memberToTransfer = nil } })) {
                Button("groups.member.transfer") {
                    guard let memberID = memberToTransfer else { return }
                    let groupID = model.summary.id
                    memberToTransfer = nil
                    Task {
                        await model.perform({ service, context in
                            _ = try await service.transferOwnership(groupID: groupID,
                                                                    newOwnerID: memberID,
                                                                    context: context)
                        }, exitsGroup: true)
                        if model.didExitGroup { dismiss() }
                    }
                }
            }
            .confirmationDialog("groups.archive.confirm",
                                isPresented: $showsArchiveConfirmation) {
                Button("groups.archive", role: .destructive) {
                    let groupID = model.summary.id
                    Task {
                        await model.perform({ service, context in
                            _ = try await service.archive(groupID: groupID, context: context)
                        }, exitsGroup: true)
                        if model.didExitGroup { dismiss() }
                    }
                }
            }
        }
        .accessibilityIdentifier("screen.group-settings")
    }
}
