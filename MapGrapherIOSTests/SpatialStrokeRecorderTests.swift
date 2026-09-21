import XCTest
import simd
@testable import MapGrapherIOS

final class SpatialStrokeRecorderTests: XCTestCase {
    func testRecordsOnlyWhileDrawingAndCommitsTwoPointStroke() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.02, maximumPointCount: 10)
        let style = try XCTUnwrap(SpatialStrokeStyle(color: .coral, widthM: 0.03))

        XCTAssertEqual(recorder.append(position: .zero), .notDrawing)
        recorder.beginStroke(style: style)
        XCTAssertEqual(recorder.append(position: .zero), .accepted)
        XCTAssertEqual(recorder.append(position: SIMD3<Float>(0.03, 0, 0)), .accepted)
        recorder.endStroke()

        XCTAssertEqual(recorder.strokes.count, 1)
        XCTAssertEqual(recorder.strokes[0].points.count, 2)
        XCTAssertEqual(recorder.pointCount, 2)
    }

    func testFiltersCameraJitterBelowMinimumDistance() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.02, maximumPointCount: 10)
        recorder.beginStroke(style: try XCTUnwrap(SpatialStrokeStyle(color: .cyan, widthM: 0.01)))

        XCTAssertEqual(recorder.append(position: .zero), .accepted)
        XCTAssertEqual(recorder.append(position: SIMD3<Float>(0.019, 0, 0)), .ignoredTooClose)
        XCTAssertEqual(recorder.append(position: SIMD3<Float>(0.021, 0, 0)), .accepted)
    }

    func testRejectsNonFiniteCameraPosition() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.02, maximumPointCount: 10)
        recorder.beginStroke(style: try XCTUnwrap(SpatialStrokeStyle(color: .yellow, widthM: 0.06)))

        XCTAssertEqual(
            recorder.append(position: SIMD3<Float>(.nan, 0, 0)),
            .rejectedInvalid
        )
        XCTAssertEqual(recorder.pointCount, 0)
    }

    func testDiscardsSinglePointStroke() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.02, maximumPointCount: 10)
        recorder.beginStroke(style: try XCTUnwrap(SpatialStrokeStyle(color: .white, widthM: 0.03)))
        XCTAssertEqual(recorder.append(position: .zero), .accepted)

        recorder.endStroke()

        XCTAssertTrue(recorder.strokes.isEmpty)
        XCTAssertEqual(recorder.pointCount, 0)
    }

    func testStopsAtSessionPointLimit() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.01, maximumPointCount: 2)
        recorder.beginStroke(style: try XCTUnwrap(SpatialStrokeStyle(color: .coral, widthM: 0.03)))

        XCTAssertEqual(recorder.append(position: .zero), .accepted)
        XCTAssertEqual(recorder.append(position: SIMD3<Float>(0.02, 0, 0)), .accepted)
        XCTAssertEqual(recorder.append(position: SIMD3<Float>(0.04, 0, 0)), .limitReached)
    }

    func testUndoAndClearOperateOnCompletedStrokes() throws {
        var recorder = SpatialStrokeRecorder(minimumPointDistance: 0.01, maximumPointCount: 10)
        let style = try XCTUnwrap(SpatialStrokeStyle(color: .coral, widthM: 0.03))
        for offset in [Float(0), Float(1)] {
            recorder.beginStroke(style: style)
            XCTAssertEqual(recorder.append(position: SIMD3<Float>(offset, 0, 0)), .accepted)
            XCTAssertEqual(recorder.append(position: SIMD3<Float>(offset + 0.02, 0, 0)), .accepted)
            recorder.endStroke()
        }

        recorder.undo()
        XCTAssertEqual(recorder.strokes.count, 1)
        XCTAssertEqual(recorder.pointCount, 2)

        recorder.clear()
        XCTAssertTrue(recorder.strokes.isEmpty)
        XCTAssertEqual(recorder.pointCount, 0)
    }

    func testStyleRejectsUnsafeWidths() {
        XCTAssertNil(SpatialStrokeStyle(color: .coral, widthM: 0))
        XCTAssertNil(SpatialStrokeStyle(color: .coral, widthM: .infinity))
        XCTAssertNil(SpatialStrokeStyle(color: .coral, widthM: 0.101))
        XCTAssertNotNil(SpatialStrokeStyle(color: .coral, widthM: 0.005))
    }
}
