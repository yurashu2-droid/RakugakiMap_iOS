import XCTest
@testable import MapGrapherCore

final class TraceDirectionTests: XCTestCase {
    func test北をまたぐ差分は最短の二度になる() {
        XCTAssertEqual(TraceDirection.relativeBearing(targetBearingDegrees: 1, trueHeadingDegrees: 359)!, 2, accuracy: 0.001)
        XCTAssertEqual(TraceDirection.relativeBearing(targetBearingDegrees: 359, trueHeadingDegrees: 1)!, -2, accuracy: 0.001)
    }

    func test東西南北の方位を計算する() {
        let origin = GeoPoint(latitude: 0, longitude: 0)!
        XCTAssertEqual(TraceDirection.bearing(from: origin, to: GeoPoint(latitude: 1, longitude: 0)!), 0, accuracy: 0.001)
        XCTAssertEqual(TraceDirection.bearing(from: origin, to: GeoPoint(latitude: 0, longitude: 1)!), 90, accuracy: 0.001)
        XCTAssertEqual(TraceDirection.bearing(from: origin, to: GeoPoint(latitude: -1, longitude: 0)!), 180, accuracy: 0.001)
        XCTAssertEqual(TraceDirection.bearing(from: origin, to: GeoPoint(latitude: 0, longitude: -1)!), 270, accuracy: 0.001)
    }

    func test無効な真北方向を使わない() {
        XCTAssertNil(TraceDirection.relativeBearing(targetBearingDegrees: 20, trueHeadingDegrees: .nan))
        XCTAssertNil(TraceDirection.relativeBearing(targetBearingDegrees: 20, trueHeadingDegrees: -1))
    }
}
