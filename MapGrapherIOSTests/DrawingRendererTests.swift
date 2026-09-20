import Foundation
import CoreGraphics
import ImageIO
import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

final class DrawingRendererTests: XCTestCase {
    func testTransparentBackgroundAndPenPixel() throws {
        let stroke = try sampleStroke(brush: .pen, x: 16, y: 16, width: 8)
        let document = try XCTUnwrap(DrawingDocument(pixelWidth: 32, pixelHeight: 32, strokes: [stroke]))
        let image = try DrawingRenderer().render(document: document)
        XCTAssertEqual(alpha(image, x: 0, y: 0), 0)
        XCTAssertGreaterThan(alpha(image, x: 16, y: 16), 0)
    }

    func testEraserClearsDrawingLayer() throws {
        let pen = try sampleStroke(brush: .pen, x: 16, y: 16, width: 12)
        let eraser = try sampleStroke(brush: .eraser, x: 16, y: 16, width: 12)
        let document = try XCTUnwrap(DrawingDocument(pixelWidth: 32, pixelHeight: 32,
                                                      strokes: [pen, eraser]))
        let image = try DrawingRenderer().render(document: document)
        XCTAssertEqual(alpha(image, x: 16, y: 16), 0)
    }

    func testSprayIsBitwiseStableForSameSeed() throws {
        for brush in [DrawingBrush.spray, .crayon] {
            let stroke = try sampleStroke(brush: brush, x: 16, y: 16, width: 12)
            let document = try XCTUnwrap(DrawingDocument(pixelWidth: 32, pixelHeight: 32,
                                                          strokes: [stroke]))
            let restored = try JSONDecoder().decode(
                DrawingDocument.self, from: JSONEncoder().encode(document)
            )
            let first = try DrawingRenderer().render(document: document)
            let second = try DrawingRenderer().render(document: restored)
            let firstData = try XCTUnwrap(first.dataProvider?.data) as Data
            let secondData = try XCTUnwrap(second.dataProvider?.data) as Data
            XCTAssertEqual(firstData, secondData)
        }
    }

    func testCheckpointMatchesFullRedraw() throws {
        var strokes: [DrawingStroke] = []
        for index in 0..<16 {
            strokes.append(try sampleStroke(brush: .pen, x: Double(3 + index * 3), y: 10, width: 2))
        }
        let cached = DrawingRenderer()
        let first = try XCTUnwrap(DrawingDocument(pixelWidth: 64, pixelHeight: 64, strokes: strokes))
        _ = try cached.render(document: first)
        strokes.append(try sampleStroke(brush: .neon, x: 20, y: 30, width: 6))
        let second = try XCTUnwrap(DrawingDocument(pixelWidth: 64, pixelHeight: 64, strokes: strokes))
        let fromCheckpoint = try cached.render(document: second)
        let fromScratch = try DrawingRenderer().render(document: second)
        let cachedData = try XCTUnwrap(fromCheckpoint.dataProvider?.data) as Data
        let freshData = try XCTUnwrap(fromScratch.dataProvider?.data) as Data
        XCTAssertEqual(cachedData, freshData)
    }

    func testUndoRedoRestoresWholeStroke() throws {
        var history = DrawingHistory(document: DrawingDocument(pixelWidth: 32, pixelHeight: 32, strokes: [])!)
        let stroke = try sampleStroke(brush: .crayon, x: 16, y: 16, width: 7)
        history.append(stroke)
        history.undo()
        XCTAssertTrue(history.document.strokes.isEmpty)
        history.redo()
        XCTAssertEqual(history.document.strokes, [stroke])
    }

    func testExporterWritesTransparentPNGWithoutSourcePhoto() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try XCTUnwrap(DrawingDocument(pixelWidth: 32, pixelHeight: 32, strokes: []))
        let prepared = try await DrawingExporter(outputDirectory: directory).export(document: document)
        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertEqual(prepared.pixelWidth, 32)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(prepared.fileURL as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(alpha(decoded, x: 0, y: 0), 0)
    }

    private func sampleStroke(brush: DrawingBrush, x: Double, y: Double, width: Double) throws -> DrawingStroke {
        try XCTUnwrap(DrawingStroke(id: UUID(), brush: brush,
                                     color: DrawingColor(red: 1, green: 0, blue: 0, alpha: 1)!,
                                     width: width, opacity: 1,
                                     points: [DrawingPoint(x: x, y: y)!], randomSeed: 123))
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              x >= 0, y >= 0, x < image.width, y < image.height else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        return bytes[y * image.width * 4 + x * 4 + 3]
    }
}
