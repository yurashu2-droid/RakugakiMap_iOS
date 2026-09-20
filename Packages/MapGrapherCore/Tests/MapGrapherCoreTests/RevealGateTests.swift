import Foundation
import XCTest
@testable import MapGrapherCore

final class RevealGateTests: XCTestCase {
    func testRevealNeedsTwoDistinctAccurateSamples() {
        var gate = RevealGate()
        let first = Date(timeIntervalSince1970: 2_000)
        let second = first.addingTimeInterval(1)

        XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: first, now: first, radiusM: 50))
        XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: first, now: first, radiusM: 50))
        XCTAssertTrue(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: second, now: second, radiusM: 50))
    }

    func testThresholdValuesAreInclusive() {
        var gate = RevealGate()
        let now = Date(timeIntervalSince1970: 2_000)

        XCTAssertFalse(gate.ingest(
            distanceM: 50, accuracyM: 25,
            timestamp: now.addingTimeInterval(-10), now: now, radiusM: 50
        ))
        XCTAssertTrue(gate.ingest(
            distanceM: 50, accuracyM: 25,
            timestamp: now.addingTimeInterval(-9), now: now, radiusM: 50
        ))
    }

    func testInvalidSampleBreaksConsecutiveSequence() {
        let first = Date(timeIntervalSince1970: 2_000)
        let next = first.addingTimeInterval(1)
        let afterNext = first.addingTimeInterval(2)
        let cases: [(name: String, distance: Double, accuracy: Double, timestamp: Date, now: Date, radius: Double)] = [
            ("範囲外", 50.01, 5, next, next, 50),
            ("距離が負", -1, 5, next, next, 50),
            ("精度が負", 20, -0.01, next, next, 50),
            ("精度が25m超", 20, 25.01, next, next, 50),
            ("未来", 20, 5, next.addingTimeInterval(1), next, 50),
            ("10秒超の古さ", 20, 5, next.addingTimeInterval(-10.01), next, 50),
            ("距離がNaN", .nan, 5, next, next, 50),
            ("精度がNaN", 20, .nan, next, next, 50),
            ("精度が無限大", 20, .infinity, next, next, 50),
            ("半径が無限大", 20, 5, next, next, .infinity),
            ("半径がゼロ", 20, 5, next, next, 0),
            ("半径が下限未満", 20, 5, next, next, 9.99),
            ("半径が上限超", 20, 5, next, next, 200.01),
        ]

        for sample in cases {
            var gate = RevealGate()
            XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: first, now: first, radiusM: 50))
            XCTAssertFalse(gate.ingest(
                distanceM: sample.distance, accuracyM: sample.accuracy,
                timestamp: sample.timestamp, now: sample.now, radiusM: sample.radius
            ), sample.name)
            XCTAssertFalse(gate.ingest(
                distanceM: 20, accuracyM: 5,
                timestamp: next, now: next, radiusM: 50
            ), sample.name)
            XCTAssertTrue(gate.ingest(
                distanceM: 20, accuracyM: 5,
                timestamp: afterNext, now: afterNext, radiusM: 50
            ), sample.name)
        }
    }

    func testOlderOutOfOrderSampleDoesNotCountAsSecondSample() {
        var gate = RevealGate()
        let first = Date(timeIntervalSince1970: 2_000)
        let older = first.addingTimeInterval(-1)
        let next = first.addingTimeInterval(1)

        XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: first, now: first, radiusM: 50))
        XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: older, now: first, radiusM: 50))
        XCTAssertTrue(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: next, now: next, radiusM: 50))
    }

    func testRevealStaysLatchedDuringExploration() {
        var gate = RevealGate()
        let first = Date(timeIntervalSince1970: 2_000)
        let second = first.addingTimeInterval(1)

        XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: first, now: first, radiusM: 50))
        XCTAssertTrue(gate.ingest(distanceM: 20, accuracyM: 5, timestamp: second, now: second, radiusM: 50))
        XCTAssertTrue(gate.ingest(distanceM: 500, accuracyM: -1, timestamp: second, now: second, radiusM: 50))
    }
}
