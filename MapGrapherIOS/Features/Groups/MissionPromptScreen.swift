import SwiftUI
import MapGrapherCore

@MainActor
struct MissionPromptScreen: View {
    let missionID: UUID
    let service: any GroupsServing
    let context: SessionContext?
    let dataMode: GroupUIDataMode
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var isWorking = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GroupPrototypeNotice(dataMode: dataMode)
                }
                Section("groups.mission.set-prompt") {
                    TextField("groups.mission.prompt-placeholder", text: $prompt,
                              axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("group.mission.prompt")
                    Text("groups.mission.prompt-once")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("groups.save") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || prompt.count > 160)
                    .accessibilityIdentifier("group.mission.prompt-save")
                }
                if let error {
                    Text(GroupUIMessage.errorKey(for: error)).foregroundStyle(.red)
                }
            }
            .navigationTitle("groups.mission.set-prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("posting.close.cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen.group-prompt")
    }

    private func save() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            _ = try await service.setPrompt(missionID: missionID, text: prompt,
                                            context: resolved)
            dismiss()
        } catch {
            self.error = error
        }
    }
}
