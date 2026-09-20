import RealityKit
import UIKit

enum ARSnapshotError: Error {
    case imageUnavailable
}

@MainActor
enum ARSnapshotWriter {
    static func capture(from view: ARView) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            view.snapshot(saveToHDR: false) { image in
                guard let image else {
                    continuation.resume(throwing: ARSnapshotError.imageUnavailable)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}
