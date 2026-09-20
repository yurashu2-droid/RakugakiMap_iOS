import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

final class ContractDecodingTests: XCTestCase {
    func testOnlyPublicClientKeysAreAccepted() {
        XCTAssertFalse(SupabaseGateway.isClientKey("replace-with-publishable-key"))
        XCTAssertFalse(SupabaseGateway.isClientKey("sb_secret_synthetic"))
        XCTAssertFalse(SupabaseGateway.isClientKey("service_role"))
        XCTAssertTrue(SupabaseGateway.isClientKey("sb_publishable_synthetic"))
        let anonPayload = Data(#"{"role":"anon"}"#.utf8).base64EncodedString()
        let servicePayload = Data(#"{"role":"service_role"}"#.utf8).base64EncodedString()
        XCTAssertTrue(SupabaseGateway.isClientKey("eyJ.\(anonPayload).synthetic"))
        XCTAssertFalse(SupabaseGateway.isClientKey("eyJ.\(servicePayload).synthetic"))
    }

    func testNearbyPhotoNullableFieldsAndLargeCount() throws {
        let data = try fixture("nearby_photos")
        let rows = try SupabaseContract.decoder.decode([NearbyPhotoDTO].self, from: data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].likeCount, 3_000_000_000)
        XCTAssertNil(rows[0].ownerName)
        XCTAssertEqual(rows[0].privacy, .onlyMe)
    }

    func testUnknownVisibilityFailsClosed() {
        let json = Data(#"{"id":"11111111-1111-4111-8111-111111111111","owner_id":"22222222-2222-4222-8222-222222222222","privacy":"PUBLIC"}"#.utf8)
        XCTAssertThrowsError(try SupabaseContract.decoder.decode(PhotoRowDTO.self, from: json))
    }

    func testCreatePhotoRequestPreservesRpcArgumentNames() throws {
        let request = CreatePhotoPinRequestDTO(title: "試験", lat: 35, lon: 139, privacy: .onlyMe,
                                                drawPermission: .friends, requiresApproval: true,
                                                photoPath: "synthetic/photos/photo.jpg", mimeType: "image/jpeg", byteSize: 123)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: SupabaseContract.encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["title", "lat", "lon", "privacy", "draw_permission", "requires_approval", "photo_path", "mime_type", "byte_size"]))
        XCTAssertNil(object["user_id"])
    }

    func testArTraceIsArrayAndMissionDateIsPlainDay() throws {
        let data = try fixture("group_summaries")
        let rows = try SupabaseContract.decoder.decode([GroupSummaryDTO].self, from: data)
        XCTAssertEqual(rows.first?.missionDate, "2026-09-21")
        XCTAssertThrowsError(try SupabaseContract.decoder.decode(GroupSummaryDTO.self, from: data))
    }

    func testARSingleLookupIsZeroOrOneElementArray() throws {
        let rows = try SupabaseContract.decoder.decode([ArExperienceDTO].self, from: fixture("ar_experience"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].anchorType, .localPlane)
        let empty = try SupabaseContract.decoder.decode([ArExperienceDTO].self, from: Data("[]".utf8))
        XCTAssertTrue(empty.isEmpty)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
