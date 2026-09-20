import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class SupabasePhotoReaderTests: XCTestCase {
    func testNearbyPhotoFixtureMapsWithoutLosingPrivacyOrLargeLikeCount() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "nearby_photos", withExtension: "json"))
        let rows = try SupabaseContract.decoder.decode([NearbyPhotoDTO].self, from: Data(contentsOf: url))
        let photo = try SupabasePhotoReader.map(try XCTUnwrap(rows.first))
        XCTAssertEqual(photo.visibility, .onlyMe)
        XCTAssertEqual(photo.drawPermission, .friends)
        XCTAssertEqual(photo.likeCount, 3_000_000_000)
        XCTAssertEqual(photo.asset.bucket, "photos")
        XCTAssertTrue(photo.requiresApproval)
    }

    func testMissingPrivateAssetPathFailsRatherThanHidingRow() throws {
        let json = Data(#"{"id":"11111111-1111-4111-8111-111111111111","owner_id":"22222222-2222-4222-8222-222222222222","photo_path":null,"latitude":35,"longitude":139,"privacy":"ANYONE","draw_permission":"ANYONE","requires_approval":false,"created_at":"2026-01-02T03:04:05Z","like_count":0,"liked_by_me":false}"#.utf8)
        let row = try SupabaseContract.decoder.decode(NearbyPhotoDTO.self, from: json)
        XCTAssertThrowsError(try SupabasePhotoReader.map(row))
    }
}
