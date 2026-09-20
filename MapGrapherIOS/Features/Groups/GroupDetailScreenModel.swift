import Combine
import Foundation
import MapGrapherCore

@MainActor
final class GroupDetailScreenModel: ObservableObject {
    @Published private(set) var summary: GroupSummary
    @Published private(set) var members: [GroupMember] = []
    @Published private(set) var participants: [GroupMissionParticipant] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var didCompleteAction = false
    @Published private(set) var didExitGroup = false
    @Published private(set) var recentInvitation: GroupInvitation?

    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode

    init(summary: GroupSummary, service: any GroupsServing,
         context: SessionContext?, dataMode: GroupUIDataMode) {
        self.summary = summary
        self.service = service
        self.context = context
        self.dataMode = dataMode
    }

    var myParticipant: GroupMissionParticipant? {
        guard let context = try? GroupUIContext.resolve(context, dataMode: dataMode) else { return nil }
        return participants.first {
            $0.participantID == context.userID && $0.missionID == summary.missionID
        }
    }

    var canSetPrompt: Bool {
        guard let context = try? GroupUIContext.resolve(context, dataMode: dataMode) else { return false }
        return summary.setterID == context.userID && summary.missionStatus == .awaitingPrompt
            && summary.missionDate.map { GroupMissionDate.state(for: $0) == .today } == true
    }

    var canAnswer: Bool {
        guard let mine = myParticipant, let date = summary.missionDate else { return false }
        return mine.isActive && !mine.answered && summary.missionStatus == .open
            && GroupMissionDate.state(for: date) == .today
    }

    var isTodayIneligible: Bool {
        summary.missionID != nil && myParticipant == nil
            && summary.missionDate.map { GroupMissionDate.state(for: $0) == .today } == true
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            let list = try await service.summaries(context: resolved)
            guard let updated = list.first(where: { $0.id == summary.id }) else {
                throw AppFailure.notFound
            }
            let loadedMembers = try await service.members(groupID: summary.id, context: resolved)
            let loadedParticipants = try await service.missionStatus(groupID: summary.id, context: resolved)
            summary = updated
            members = loadedMembers
            participants = loadedParticipants
            state = .content
        } catch {
            self.error = error
            state = .error
        }
    }

    func perform(_ operation: @escaping (any GroupsServing, SessionContext) async throws -> Void,
                 exitsGroup: Bool = false) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            try await operation(service, resolved)
            if exitsGroup {
                didExitGroup = true
            } else {
                await load()
            }
            didCompleteAction = true
        } catch {
            self.error = error
        }
    }

    func invite(uniqueID: String) async -> Bool {
        guard !isWorking else { return false }
        let value = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            error = GroupUIError.invalidInput
            return false
        }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            recentInvitation = try await service.invite(groupID: summary.id,
                                                        userUniqueID: value, context: resolved)
            didCompleteAction = true
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func cancelRecentInvitation() async {
        guard let invitation = recentInvitation else { return }
        await perform { service, context in
            _ = try await service.cancelInvitation(id: invitation.id, context: context)
        }
        if error == nil { recentInvitation = nil }
    }

    func clearActionNotice() {
        didCompleteAction = false
        error = nil
    }
}
