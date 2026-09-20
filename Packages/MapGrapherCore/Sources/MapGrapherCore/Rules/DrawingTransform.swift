import Foundation

public struct DrawingTransform: Equatable, Sendable {
    public let imageWidth: Double
    public let imageHeight: Double
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let zoom: Double
    public let panX: Double
    public let panY: Double
    public let rotationRadians: Double

    private var scale: Double {
        min(viewportWidth / imageWidth, viewportHeight / imageHeight) * zoom
    }

    public init?(imageWidth: Double, imageHeight: Double,
                 viewportWidth: Double, viewportHeight: Double,
                 zoom: Double = 1, panX: Double = 0, panY: Double = 0,
                 rotationRadians: Double = 0) {
        guard [imageWidth, imageHeight, viewportWidth, viewportHeight,
               zoom, panX, panY, rotationRadians].allSatisfy(\.isFinite),
              imageWidth >= 1, imageHeight >= 1,
              viewportWidth > 0, viewportHeight > 0,
              viewportWidth <= 1_000_000, viewportHeight <= 1_000_000,
              abs(panX) <= 1_000_000, abs(panY) <= 1_000_000,
              abs(rotationRadians) <= 2 * .pi,
              zoom > 0, zoom <= 32,
              (min(viewportWidth / imageWidth, viewportHeight / imageHeight) * zoom).isFinite else {
            return nil
        }
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.rotationRadians = rotationRadians
    }

    public func imagePoint(fromView point: DrawingPoint) -> DrawingPoint? {
        let dx = point.x - viewportWidth / 2 - panX
        let dy = point.y - viewportHeight / 2 - panY
        let c = cos(rotationRadians)
        let s = sin(rotationRadians)
        let x = (dx * c + dy * s) / scale + imageWidth / 2
        let y = (-dx * s + dy * c) / scale + imageHeight / 2
        guard x >= 0, x < imageWidth, y >= 0, y < imageHeight else { return nil }
        return DrawingPoint(x: x, y: y)
    }

    public func viewPoint(fromImage point: DrawingPoint) -> DrawingPoint {
        let dx = (point.x - imageWidth / 2) * scale
        let dy = (point.y - imageHeight / 2) * scale
        let c = cos(rotationRadians)
        let s = sin(rotationRadians)
        return DrawingPoint(x: viewportWidth / 2 + panX + dx * c - dy * s,
                            y: viewportHeight / 2 + panY + dx * s + dy * c)!
    }
}
