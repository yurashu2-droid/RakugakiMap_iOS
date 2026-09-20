import Foundation
import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

final class SubmissionIntegrationTests: XCTestCase {
    func testPhotoV2RequestUsesExactRPCArgumentNames() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let request = CreatePhotoPinV2RequestDTO(
            clientRequestId: id, title: "写真", lat: 35, lon: 139,
            privacy: .anyone, drawPermission: .friends, requiresApproval: true,
            photoPath: "owner/photos/image.jpg", mimeType: "image/jpeg", byteSize: 4
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SupabaseContract.encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "client_request_id", "title", "lat", "lon", "privacy", "draw_permission",
            "requires_approval", "photo_path", "mime_type", "byte_size"
        ]))
        XCTAssertEqual(object["client_request_id"] as? String, id.uuidString)
    }

    func testRakugakiV2RequestUsesExactRPCArgumentNames() throws {
        let request = CreateRakugakiV2RequestDTO(clientRequestId: UUID(), targetPhotoId: UUID(),
                                                 targetAssetPath: "owner/rakugakis/image.png")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SupabaseContract.encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "client_request_id", "target_photo_id", "target_asset_path"
        ]))
    }
}
