import ARKit
import Foundation

enum ARWorldMapCaptureError: Error {
    case mappingNotReady
    case placementNotLocked
    case sessionUnavailable
    case packageInvalid
    case cancelled
}

@MainActor
enum ARWorldMapCaptureRequest {
    static func capture(from session: ARSession) async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { worldMap, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let worldMap {
                    continuation.resume(returning: worldMap)
                } else {
                    continuation.resume(throwing: ARWorldMapCaptureError.sessionUnavailable)
                }
            }
        }
    }
}
