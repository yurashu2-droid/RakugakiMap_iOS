import Combine
import Foundation
import MapGrapherCore

@MainActor
final class NotificationScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var rows: [GroupNotification] = []
    @Published private(set) var summaries: [GroupSummary] = []
    @Published private(set) var error: Error?
    @Published private(set) var isWorking = false
    @Published private(set) var targetUnavailable = false

    private let service: any GroupsServing
    private let context: SessionContext?
    private let dataMode: GroupUIDataMode

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
            rows = try await service.notifications(limit: 50, before: nil, context: resolved)
            summaries = try await service.summaries(context: resolved)
            state = rows.isEmpty ? .empty : .content
        } catch {
            self.error = error
            state = .error
        }
    }

    func markRead(_ notification: GroupNotification) async -> GroupSummary? {
        guard !isWorking else { return nil }
        isWorking = true
        error = nil
        targetUnavailable = false
        defer { isWorking = false }
        do {
            let resolved = try GroupUIContext.resolve(context, dataMode: dataMode)
            let updated = try await service.markNotificationRead(id: notification.id,
                                                                 context: resolved)
            if let index = rows.firstIndex(where: { $0.id == updated.id }) {
                rows[index] = updated
            }
            guard let groupID = updated.groupID,
                  let summary = summaries.first(where: { $0.id == groupID }) else {
                targetUnavailable = true
                return nil
            }
            return summary
        } catch {
            self.error = error
            return nil
        }
    }

    func clearTargetNotice() { targetUnavailable = false }
}
