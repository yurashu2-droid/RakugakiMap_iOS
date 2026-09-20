import XCTest
@testable import MapGrapherCore

final class TraceDistanceBandTests: XCTestCase {
    func test距離帯の境界() {
        XCTAssertEqual(TraceDistanceBand.classify(0), .immediate)
        XCTAssertEqual(TraceDistanceBand.classify(14.99), .immediate)
        XCTAssertEqual(TraceDistanceBand.classify(15), .near)
        XCTAssertEqual(TraceDistanceBand.classify(49.99), .near)
        XCTAssertEqual(TraceDistanceBand.classify(50), .medium)
        XCTAssertEqual(TraceDistanceBand.classify(99.99), .medium)
        XCTAssertEqual(TraceDistanceBand.classify(100), .far)
    }

    func test無効な距離を表示しない() {
        XCTAssertNil(TraceDistanceBand.classify(-1))
        XCTAssertNil(TraceDistanceBand.classify(.infinity))
        XCTAssertNil(TraceDistanceBand.classify(.nan))
    }
}
