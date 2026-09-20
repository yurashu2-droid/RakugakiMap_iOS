import Foundation
import XCTest
@testable import MapGrapherCore

final class IdentityTests: XCTestCase {
    func testGeoPointAcceptsInclusiveCoordinateBounds() {
        XCTAssertEqual(GeoPoint(latitude: 90, longitude: -180)?.latitude, 90)
        XCTAssertEqual(GeoPoint(latitude: -90, longitude: 180)?.longitude, 180)
        XCTAssertNotNil(GeoPoint(latitude: 0, longitude: 0))
    }

    func testGeoPointRejectsCoordinatesOutsideEarthBounds() {
        XCTAssertNil(GeoPoint(latitude: 90.0001, longitude: 0))
        XCTAssertNil(GeoPoint(latitude: -90.0001, longitude: 0))
        XCTAssertNil(GeoPoint(latitude: 0, longitude: 180.0001))
        XCTAssertNil(GeoPoint(latitude: 0, longitude: -180.0001))
    }

    func testGeoPointRejectsNonFiniteCoordinates() {
        XCTAssertNil(GeoPoint(latitude: .nan, longitude: 0))
        XCTAssertNil(GeoPoint(latitude: .infinity, longitude: 0))
        XCTAssertNil(GeoPoint(latitude: 0, longitude: -.infinity))
    }

    func testGeoPointDecodingCannotBypassCoordinateValidation() {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(
            try decoder.decode(GeoPoint.self, from: Data(#"{"latitude":91,"longitude":0}"#.utf8))
        )
    }

    func testVisibilityUsesServerValuesAndRejectsUnknownValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(String(decoding: try encoder.encode(Visibility.anyone), as: UTF8.self), #""ANYONE""#)
        XCTAssertEqual(String(decoding: try encoder.encode(Visibility.friends), as: UTF8.self), #""FRIENDS""#)
        XCTAssertEqual(String(decoding: try encoder.encode(Visibility.onlyMe), as: UTF8.self), #""ONLY_ME""#)
        XCTAssertThrowsError(try decoder.decode(Visibility.self, from: Data(#""PUBLIC""#.utf8)))
    }

    func testApprovalStatusRejectsUnknownValueWithoutTreatingItAsApproved() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(String(decoding: try encoder.encode(ApprovalStatus.pending), as: UTF8.self), #""PENDING""#)
        XCTAssertEqual(String(decoding: try encoder.encode(ApprovalStatus.approved), as: UTF8.self), #""APPROVED""#)
        XCTAssertEqual(String(decoding: try encoder.encode(ApprovalStatus.rejected), as: UTF8.self), #""REJECTED""#)
        XCTAssertThrowsError(try decoder.decode(ApprovalStatus.self, from: Data(#""UNKNOWN""#.utf8)))
    }

    func testSessionContextChangesWithEpochAndAccount() {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let epoch = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let nextEpoch = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        let original = SessionContext(userID: userID, epoch: epoch)
        XCTAssertEqual(original, SessionContext(userID: userID, epoch: epoch))
        XCTAssertNotEqual(original, SessionContext(userID: userID, epoch: nextEpoch))
        XCTAssertNotEqual(original, SessionContext(userID: otherUserID, epoch: epoch))
    }
}
