import Foundation
import MapGrapherCore

struct PhotoRakugaki: Identifiable, Equatable, Sendable {
    let id: UUID
    let authorName: String
    let createdAt: Date
    let asset: AssetReference
}

@MainActor
protocol PhotoRakugakiReading {
    func approved(photoID: UUID) async throws -> [PhotoRakugaki]
}

@MainActor
struct FakePhotoRakugakiReader: PhotoRakugakiReading {
    func approved(photoID: UUID) async throws -> [PhotoRakugaki] { [] }
}
