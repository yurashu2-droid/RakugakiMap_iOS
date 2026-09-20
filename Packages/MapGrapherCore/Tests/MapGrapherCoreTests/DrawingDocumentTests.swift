import XCTest
@testable import MapGrapherCore

final class DrawingDocumentTests: XCTestCase {
    func testCodableRoundTripKeepsPixelPointsAndSeed() throws {
        let stroke = try XCTUnwrap(DrawingStroke(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            brush: .spray, color: DrawingColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.8)!,
            width: 12, opacity: 0.7,
            points: [DrawingPoint(x: 0, y: 0)!, DrawingPoint(x: 999, y: 499)!],
            randomSeed: 42
        ))
        let document = try XCTUnwrap(DrawingDocument(pixelWidth: 1_000, pixelHeight: 500, strokes: [stroke]))
        let restored = try JSONDecoder().decode(DrawingDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored, document)
        XCTAssertEqual(restored.strokes[0].randomSeed, 42)
    }

    func testInvalidDimensionsOrOutOfBoundsPointAreRejected() throws {
        let stroke = try XCTUnwrap(DrawingStroke(
            id: UUID(), brush: .pen, color: DrawingColor(red: 1, green: 0, blue: 0, alpha: 1)!,
            width: 2, opacity: 1, points: [DrawingPoint(x: 201, y: 10)!], randomSeed: 1
        ))
        XCTAssertNil(DrawingDocument(pixelWidth: 0, pixelHeight: 100, strokes: []))
        XCTAssertNil(DrawingDocument(pixelWidth: 200, pixelHeight: 100, strokes: [stroke]))
    }

    func testUnknownBrushAndSchemaFailOnRestore() throws {
        let unknownBrush = Data(#"{"id":"11111111-1111-4111-8111-111111111111","brush":"watercolor","color":{"red":1,"green":0,"blue":0,"alpha":1},"width":3,"opacity":1,"points":[{"x":1,"y":1}],"randomSeed":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DrawingStroke.self, from: unknownBrush))
        let unknownVersion = Data(#"{"schemaVersion":99,"pixelWidth":100,"pixelHeight":100,"strokes":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DrawingDocument.self, from: unknownVersion))
    }
}
