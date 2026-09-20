import Combine
import Foundation
import MapGrapherCore

enum TraceExplorerState: Equatable {
    case idle
    case locating
    case permissionDenied
    case preciseLocationRequired
    case ready
    case unavailable
}

@MainActor
final class TraceExplorerModel: ObservableObject {
    @Published private(set) var state: TraceExplorerState = .idle
    @Published private(set) var traces: [ARTrace] = []

    private let context: SessionContext
    private let repository: any ARExperienceServing
    private let location: any ARLocationProviding
    private let session: any SessionProviding
    private let clock: @Sendable () -> Date
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(context: SessionContext, repository: any ARExperienceServing,
         location: any ARLocationProviding, session: any SessionProviding,
         clock: @escaping @Sendable () -> Date = Date.init) {
        self.context = context; self.repository = repository
        self.location = location; self.session = session; self.clock = clock
    }

    func start() {
        stop()
        guard location.access != .denied else { state = .permissionDenied; return }
        let token = generation
        let stream = location.updates()
        location.start()
        state = .locating
        task = Task { [weak self] in
            guard let self else { return }
            var lastQuery: Date?
            for await sample in stream {
                guard !Task.isCancelled, self.generation == token else { return }
                guard await self.session.isCurrent(self.context) else { self.stop(); return }
                if self.location.access == .denied {
                    self.traces = []; self.state = .permissionDenied; self.location.stop(); return
                }
                if self.location.access == .reducedAccuracy {
                    self.traces = []; self.state = .preciseLocationRequired; continue
                }
                let age = self.clock().timeIntervalSince(sample.timestamp)
                guard (0...10).contains(age), sample.horizontalAccuracyM <= 25 else {
                    self.traces = []; self.state = .locating; continue
                }
                if let lastQuery, self.clock().timeIntervalSince(lastQuery) < 5 { continue }
                lastQuery = self.clock()
                do {
                    let result = try await self.repository.nearbyTraces(
                        at: sample.point, context: self.context)
                    guard self.generation == token,
                          await self.session.isCurrent(self.context) else { return }
                    self.traces = result
                    self.state = .ready
                } catch {
                    guard self.generation == token else { return }
                    self.traces = []
                    self.state = .unavailable
                }
            }
            guard self.generation == token else { return }
            self.traces = []
            self.state = self.location.access == .denied ? .permissionDenied : .unavailable
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        location.stop()
        traces = []
        state = .idle
    }
}
