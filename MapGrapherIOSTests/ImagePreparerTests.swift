import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MapGrapherIOS

final class ImagePreparerTests: XCTestCase {
    func testLargeImageIsDownsampledAndGPSMetadataIsRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 2400, height: 1200,
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0,
                                             kCGImagePropertyGPSLongitude: 139.0]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let prepared = try await ImagePreparer(outputDirectory: directory).prepare(input: input)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.pixelWidth, 1600)
        XCTAssertEqual(prepared.pixelHeight, 800)
        XCTAssertGreaterThan(prepared.byteSize, 0)
        XCTAssertEqual(prepared.sha256.count, 64)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(prepared.fileURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testInvalidImageDoesNotCreateOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("invalid.jpg")
        try Data("not an image".utf8).write(to: input)

        do {
            _ = try await ImagePreparer(outputDirectory: directory).prepare(input: input)
            XCTFail("不正画像は受理されない")
        } catch {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        }
    }
}
