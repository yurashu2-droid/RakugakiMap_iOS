import UIKit
import XCTest
@testable import MapGrapherIOS

@MainActor
final class PhotoCompositeRendererTests: XCTestCase {
    func testTransparentDrawingKeepsPhotoVisibleOutsideStrokes() {
        let photo = image(size: CGSize(width: 8, height: 4), opaque: true) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        let drawing = image(size: CGSize(width: 8, height: 4), opaque: false) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        let combined = PhotoCompositeRenderer.render(photo: photo, overlays: [drawing])

        XCTAssertEqual(combined.size, photo.size)
        XCTAssertEqual(pixel(at: CGPoint(x: 1, y: 1), in: combined), [0, 0, 255, 255])
        XCTAssertEqual(pixel(at: CGPoint(x: 6, y: 1), in: combined), [255, 0, 0, 255])
    }

    private func image(size: CGSize, opaque: Bool,
                       draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private func pixel(at point: CGPoint, in image: UIImage) -> [UInt8] {
        guard let cgImage = image.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: 8 * 4 * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &bytes, width: 8, height: 4,
                                      bitsPerComponent: 8, bytesPerRow: 8 * 4,
                                      space: colorSpace, bitmapInfo: bitmap) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 8, height: 4))
        let offset = (Int(point.y) * 8 + Int(point.x)) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
