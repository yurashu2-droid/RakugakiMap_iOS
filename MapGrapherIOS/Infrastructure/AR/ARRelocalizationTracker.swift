import Foundation

enum ARRelocalizationState: Equatable {
    case idle
    case relocalizing
    case localized
    case timedOut
    case corruptMap
}

struct ARRelocalizationTracker: Equatable {
    let anchorName: String
    private(set) var state: ARRelocalizationState = .idle

    init?(anchorName: String) {
        guard ARWorldMapArchive.isValidAnchorName(anchorName) else { return nil }
        self.anchorName = anchorName
    }

    mutating func start() {
        state = .relocalizing
    }

    mutating func ingest(anchorNames: [String?]) {
        guard state == .relocalizing,
              anchorNames.compactMap({ $0 }).contains(anchorName) else { return }
        state = .localized
    }

    mutating func timeout() {
        guard state == .relocalizing else { return }
        state = .timedOut
    }

    mutating func markCorrupt() {
        state = .corruptMap
    }

    mutating func cancel() {
        state = .idle
    }
}
