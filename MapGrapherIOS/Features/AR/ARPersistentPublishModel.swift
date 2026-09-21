import Combine
import Foundation
import MapGrapherCore

@MainActor
final class ARPersistentPublishModel: ObservableObject {
    enum State: Equatable {
        case scanning
        case capturing
        case uploading
        case published
        case failed(retryable: Bool)
    }

    @Published private(set) var state: State = .scanning
    @Published private(set) var experience: ArExperience?
    @Published private(set) var error: Error?

    private var capturedPackage: PersistentARPackage?

    var hasCapturedPackage: Bool { capturedPackage != nil }

    func publish(
        capture: @MainActor () async throws -> PersistentARPackage,
        upload: @MainActor (PersistentARPackage) async throws -> ArExperience
    ) async {
        guard state != .capturing, state != .uploading, state != .published else { return }
        error = nil
        experience = nil

        do {
            let package: PersistentARPackage
            if let capturedPackage {
                package = capturedPackage
            } else {
                state = .capturing
                package = try await capture()
                try Task.checkCancellation()
                capturedPackage = package
            }

            state = .uploading
            experience = try await upload(package)
            try Task.checkCancellation()
            state = .published
            capturedPackage = nil
        } catch is CancellationError {
            error = AppFailure.cancelled
            state = .failed(retryable: capturedPackage != nil)
        } catch {
            self.error = error
            state = .failed(retryable: capturedPackage != nil)
        }
    }

    func cancelSession() {
        capturedPackage = nil
        experience = nil
        error = nil
        state = .scanning
    }
}
