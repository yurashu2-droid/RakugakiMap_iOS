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
    /// ARWorldMapはSendableではないため、ARKitのcallback内でarchiveし、
    /// actor境界を越える値はDataだけに限定する。
    static func captureArchive(
        from session: ARSession,
        requiredAnchorName: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { worldMap, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let worldMap {
                    do {
                        continuation.resume(returning: try ARWorldMapArchive.encode(
                            worldMap,
                            requiredAnchorName: requiredAnchorName
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: ARWorldMapCaptureError.sessionUnavailable)
                }
            }
        }
    }
}
