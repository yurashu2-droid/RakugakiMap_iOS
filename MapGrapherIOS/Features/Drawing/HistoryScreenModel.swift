import Combine

@MainActor
final class HistoryScreenModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var items: [RakugakiHistoryItem] = []
    @Published private(set) var error: Error?

    private let service: any SocialProfileUIService

    init(service: any SocialProfileUIService) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        error = nil
        do {
            let pending = try await service.pendingRakugakis()
            let approved = try await service.historyRakugakis()
            items = pending + approved
            state = items.isEmpty ? .empty : .content
        } catch {
            items = []
            self.error = error
            state = .error
        }
    }
}

@MainActor
final class ApprovalScreenModel: ObservableObject {
    @Published private(set) var item: RakugakiHistoryItem
    @Published private(set) var isWorking = false
    @Published private(set) var error: Error?
    @Published private(set) var didCompleteAction = false

    private let service: any SocialProfileUIService

    init(item: RakugakiHistoryItem, service: any SocialProfileUIService) {
        self.item = item
        self.service = service
    }

    func setApproval(_ approved: Bool) async {
        guard item.canModerate, !isWorking, item.status.isPendingStatus else { return }
        isWorking = true
        didCompleteAction = false
        error = nil
        defer { isWorking = false }
        do {
            item = try await service.approveRakugaki(id: item.id, approved: approved)
            didCompleteAction = true
        } catch {
            self.error = error
        }
    }
}
