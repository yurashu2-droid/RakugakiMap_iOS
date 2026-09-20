import Foundation
import XCTest
@testable import MapGrapherIOS

@MainActor
final class SupabasePhotoRakugakiReaderTests: XCTestCase {
    func testApprovedHistoryUsesPrivateRakugakiPath() throws {
        let photoID = UUID()
        let row = PendingRakugakiDTO(id: UUID(), photoId: photoID,
            authorId: UUID(), authorName: "作者", authorAvatarPath: nil,
            assetPath: "owner/rakugakis/drawing.png", status: .approved,
            createdAt: Date())

        let result = try SupabasePhotoRakugakiReader.map(row, photoID: photoID)

        XCTAssertEqual(result.asset.bucket, "rakugakis")
        XCTAssertEqual(result.asset.path, "owner/rakugakis/drawing.png")
        XCTAssertEqual(result.authorName, "作者")
    }

    func testUnapprovedOrUnrelatedHistoryIsRejected() {
        let photoID = UUID()
        let row = PendingRakugakiDTO(id: UUID(), photoId: photoID,
            authorId: UUID(), authorName: nil, authorAvatarPath: nil,
            assetPath: "owner/rakugakis/drawing.png", status: .pending,
            createdAt: Date())

        XCTAssertThrowsError(try SupabasePhotoRakugakiReader.map(row, photoID: photoID))
        let unrelated = PendingRakugakiDTO(id: row.id, photoId: UUID(),
            authorId: row.authorId, authorName: nil, authorAvatarPath: nil,
            assetPath: row.assetPath, status: .approved, createdAt: row.createdAt)
        XCTAssertThrowsError(try SupabasePhotoRakugakiReader.map(unrelated, photoID: photoID))
    }
}
