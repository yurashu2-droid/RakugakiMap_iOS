import CoreGraphics
import Foundation
import MapGrapherCore

enum DrawingRenderError: Error {
    case contextUnavailable
    case imageUnavailable
}

/// 確定した筆跡だけを再描画する。16筆ごとに一枚のcheckpointを保持する。
final class DrawingRenderer {
    private var checkpoint: (strokes: [DrawingStroke], image: CGImage)?

    func render(document: DrawingDocument) throws -> CGImage {
        let width = document.pixelWidth
        let height = document.pixelHeight
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw DrawingRenderError.contextUnavailable
        }
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let start: Int
        if let checkpoint,
           checkpoint.image.width == width, checkpoint.image.height == height,
           document.strokes.count >= checkpoint.strokes.count,
           Array(document.strokes.prefix(checkpoint.strokes.count)) == checkpoint.strokes {
            context.draw(checkpoint.image, in: CGRect(x: 0, y: 0,
                                                      width: CGFloat(width), height: CGFloat(height)))
            start = checkpoint.strokes.count
        } else {
            start = 0
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for stroke in document.strokes.dropFirst(start) {
            draw(stroke, in: context)
        }
        guard let image = context.makeImage() else { throw DrawingRenderError.imageUnavailable }
        if document.strokes.count >= 16 && document.strokes.count.isMultiple(of: 16) {
            checkpoint = (document.strokes, image)
        }
        return image
    }

    private func draw(_ stroke: DrawingStroke, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let color = stroke.color
        let rgba = CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green),
                           blue: CGFloat(color.blue), alpha: CGFloat(color.alpha * stroke.opacity))
        context.setBlendMode(stroke.brush == .eraser ? .clear : .normal)
        switch stroke.brush {
        case .pen, .eraser:
            drawLine(stroke.points, width: stroke.width, color: rgba, in: context)
        case .neon:
            let outer = CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green),
                                blue: CGFloat(color.blue), alpha: CGFloat(color.alpha * stroke.opacity * 0.12))
            let middle = CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green),
                                 blue: CGFloat(color.blue), alpha: CGFloat(color.alpha * stroke.opacity * 0.35))
            let core = CGColor(srgbRed: 1, green: 1, blue: 1,
                               alpha: CGFloat(color.alpha * stroke.opacity * 0.8))
            drawLine(stroke.points, width: stroke.width * 2.8, color: outer, in: context)
            drawLine(stroke.points, width: stroke.width * 1.5, color: middle, in: context)
            drawLine(stroke.points, width: max(1, stroke.width * 0.35), color: core, in: context)
        case .crayon:
            drawParticles(stroke, density: 10, spread: 0.45, particleSize: 0.16,
                          color: rgba, in: context)
        case .spray:
            drawParticles(stroke, density: 22, spread: 0.8, particleSize: 0.08,
                          color: rgba, in: context)
        }
    }

    private func drawLine(_ points: [DrawingPoint], width: Double, color: CGColor,
                          in context: CGContext) {
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(CGFloat(width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if points.count == 1, let point = points.first {
            context.fillEllipse(in: CGRect(x: CGFloat(point.x - width / 2),
                                           y: CGFloat(point.y - width / 2),
                                           width: CGFloat(width), height: CGFloat(width)))
            return
        }
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
        }
        context.strokePath()
    }

    private func drawParticles(_ stroke: DrawingStroke, density: Int, spread: Double,
                               particleSize: Double, color: CGColor, in context: CGContext) {
        var random = DrawingRandom(seed: stroke.randomSeed)
        context.setFillColor(color)
        let radius = stroke.width * spread / 2
        let size = max(0.5, stroke.width * particleSize)
        var previous: DrawingPoint?
        for point in stroke.points {
            let steps: Int
            if let previous {
                let distance = hypot(point.x - previous.x, point.y - previous.y)
                steps = max(1, min(1_000, Int(ceil(distance / max(1, stroke.width / 4)))))
            } else { steps = 1 }
            for index in 1...steps {
                let fraction = Double(index) / Double(steps)
                let x = previous.map { $0.x + (point.x - $0.x) * fraction } ?? point.x
                let y = previous.map { $0.y + (point.y - $0.y) * fraction } ?? point.y
                for _ in 0..<density {
                    let angle = random.unit() * .pi * 2
                    let distance = sqrt(random.unit()) * radius
                    context.fillEllipse(in: CGRect(x: CGFloat(x + cos(angle) * distance - size / 2),
                                                   y: CGFloat(y + sin(angle) * distance - size / 2),
                                                   width: CGFloat(size), height: CGFloat(size)))
                }
            }
            previous = point
        }
    }
}

private struct DrawingRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9e3779b97f4a7c15 : seed }
    mutating func unit() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}
