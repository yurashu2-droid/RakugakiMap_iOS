import Foundation
import RealityKit
import UIKit

enum ARSnapshotError: Error {
    case imageUnavailable
    case cancelled
}

@MainActor
enum ARSnapshotWriter {
    static func capture(from view: ARView) async throws -> UIImage {
        guard !Task.isCancelled else { throw ARSnapshotError.cancelled }
        let request = ARSnapshotRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                view.snapshot(saveToHDR: false) { image in
                    request.complete(image)
                }
            }
        } onCancel: {
            request.cancel()
        }
    }
}

/// snapshotの完了とTask取消しが競合してもcontinuationを一度だけ再開する。
private final class ARSnapshotRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var isCancelled = false

    func install(_ continuation: CheckedContinuation<UIImage, Error>) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(throwing: ARSnapshotError.cancelled)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func complete(_ image: UIImage?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        if let image {
            continuation.resume(returning: image)
        } else {
            continuation.resume(throwing: ARSnapshotError.imageUnavailable)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: ARSnapshotError.cancelled)
    }
}
