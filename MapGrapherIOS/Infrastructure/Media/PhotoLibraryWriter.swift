import Foundation
import Photos

enum PhotoLibraryWriteError: Error {
    case denied
}

struct PhotoLibraryWriter {
    func saveImage(at url: URL) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { result in
                    continuation.resume(returning: result)
                }
            }
        }
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryWriteError.denied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            } completionHandler: { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: PhotoLibraryWriteError.denied) }
            }
        }
    }
}
