import XCTest
@testable import MapGrapherIOS

final class ARRelocalizationTests: XCTestCase {
    func testOnlyExactNamedAnchorCompletesRelocalization() throws {
        var tracker = try XCTUnwrap(ARRelocalizationTracker(
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001"))
        tracker.start()
        tracker.ingest(anchorNames: [nil, "rakugaki:other"])
        XCTAssertEqual(tracker.state, .relocalizing)

        tracker.ingest(anchorNames: [
            "rakugaki:00000000-0000-0000-0000-000000000001"
        ])

        XCTAssertEqual(tracker.state, .localized)
    }

    func testTimeoutIsRetryableAndRestartReturnsToRelocalizing() throws {
        var tracker = try XCTUnwrap(ARRelocalizationTracker(
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001"))
        tracker.start()
        tracker.timeout()
        XCTAssertEqual(tracker.state, .timedOut)

        tracker.start()

        XCTAssertEqual(tracker.state, .relocalizing)
    }

    func testCancelClearsRelocalizationEpoch() throws {
        var tracker = try XCTUnwrap(ARRelocalizationTracker(
            anchorName: "rakugaki:00000000-0000-0000-0000-000000000001"))
        tracker.start()

        tracker.cancel()
        tracker.ingest(anchorNames: [
            "rakugaki:00000000-0000-0000-0000-000000000001"
        ])

        XCTAssertEqual(tracker.state, .idle)
    }

    func testInvalidAnchorNameIsRejected() {
        XCTAssertNil(ARRelocalizationTracker(anchorName: "../anchor"))
    }
}
