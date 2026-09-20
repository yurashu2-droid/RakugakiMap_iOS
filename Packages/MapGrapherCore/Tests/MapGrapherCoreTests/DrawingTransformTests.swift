import XCTest
@testable import MapGrapherCore

final class DrawingTransformTests: XCTestCase {
    func testAspectFitRejectsLetterboxTouch() throws {
        let transform = try XCTUnwrap(DrawingTransform(imageWidth: 1_000, imageHeight: 500,
                                                        viewportWidth: 500, viewportHeight: 500))
        XCTAssertNil(transform.imagePoint(fromView: DrawingPoint(x: 250, y: 100)!))
        XCTAssertEqual(transform.imagePoint(fromView: DrawingPoint(x: 250, y: 250)!),
                       DrawingPoint(x: 500, y: 250))
    }

    func testInversePanZoomRotationReturnsOriginalPixel() throws {
        let transform = try XCTUnwrap(DrawingTransform(imageWidth: 1_000, imageHeight: 500,
                                                        viewportWidth: 400, viewportHeight: 300,
                                                        zoom: 2.5, panX: 24, panY: -12,
                                                        rotationRadians: .pi / 2))
        let imagePoint = DrawingPoint(x: 300, y: 200)!
        let displayed = transform.viewPoint(fromImage: imagePoint)
        let result = try XCTUnwrap(transform.imagePoint(fromView: displayed))
        XCTAssertEqual(result.x, imagePoint.x, accuracy: 0.000_001)
        XCTAssertEqual(result.y, imagePoint.y, accuracy: 0.000_001)
    }

    func testInvalidZoomAndViewportAreRejected() {
        XCTAssertNil(DrawingTransform(imageWidth: 100, imageHeight: 100,
                                      viewportWidth: 0, viewportHeight: 100))
        XCTAssertNil(DrawingTransform(imageWidth: 100, imageHeight: 100,
                                      viewportWidth: 100, viewportHeight: 100, zoom: .nan))
    }
}
