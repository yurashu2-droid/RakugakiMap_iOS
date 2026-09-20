import Combine
import Foundation
import MapGrapherCore

@MainActor
final class GroupListScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var groups: [GroupSummary] = []
    @Published private(set) var invitations: [GroupInvitationSummary] = []
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var didCompleteAction = false

    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private var createRequestID = UUID()
    private var createPayload: String?

    init(service: any GroupsServing, context: SessionContext?, dataMode: GroupUIDataMode) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            groups = try await service.summaries(context: resolved)
            invitations = try await service.invitations(context: resolved)
            state = groups.isEmpty ? .empty : .content
        } catch {
            groups = []
            invitations = []
            self.error = error
            state = .error
        }
    }

    func create(name: String, description: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            let payload = name.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + description
            if createPayload != payload {
                createPayload = payload
                createRequestID = UUID()
            }
            _ = try await service.createGroup(requestID: createRequestID, name: name,
                                              description: description, context: resolved)
            createRequestID = UUID()
            createPayload = nil
            await load()
            didCompleteAction = true
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func respond(to invitation: GroupInvitationSummary, accepted: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            _ = try await service.respondInvitation(id: invitation.id, accepted: accepted,
                                                    context: resolved)
            invitations.removeAll { $0.id == invitation.id }
            if accepted {
                groups = try await service.summaries(context: resolved)
                state = groups.isEmpty ? .empty : .content
            }
            didCompleteAction = true
        } catch {
            self.error = error
        }
    }

    func clearActionNotice() {
        didCompleteAction = false
    }
}

@MainActor
final class GroupCreateScreenModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var error: Error?

    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode
    private var createRequestID = UUID()
    private var createPayload: String?

    init(service: any GroupsServing, context: SessionContext?, dataMode: GroupUIDataMode) {
        self.service = service
        self.context = context
        self.dataMode = dataMode
    }

    func create(name: String, description: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            let payload = name.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + description
            if createPayload != payload {
                createPayload = payload
                createRequestID = UUID()
            }
            _ = try await service.createGroup(requestID: createRequestID, name: name,
                                              description: description, context: resolved)
            createRequestID = UUID()
            createPayload = nil
            return true
        } catch {
            self.error = error
            return false
        }
    }
}
