import Foundation
import simd

enum SpatialBrushColor: String, CaseIterable, Equatable, Sendable {
    case coral
    case cyan
    case yellow
    case white
}

struct SpatialStrokeStyle: Equatable, Sendable {
    let color: SpatialBrushColor
    let widthM: Float

    init?(color: SpatialBrushColor, widthM: Float) {
        guard widthM.isFinite, (0.005...0.1).contains(widthM) else { return nil }
        self.color = color
        self.widthM = widthM
    }
}

struct SpatialStrokePoint: Equatable, Sendable {
    let x: Float
    let y: Float
    let z: Float

    init?(position: SIMD3<Float>) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        x = position.x
        y = position.y
        z = position.z
    }

    var position: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

struct SpatialStroke: Equatable, Sendable {
    let style: SpatialStrokeStyle
    let points: [SpatialStrokePoint]
}

enum SpatialStrokeAppendResult: Equatable, Sendable {
    case accepted
    case notDrawing
    case ignoredTooClose
    case rejectedInvalid
    case limitReached
}

struct SpatialStrokeRecorder: Equatable, Sendable {
    private struct ActiveStroke: Equatable, Sendable {
        let style: SpatialStrokeStyle
        var points: [SpatialStrokePoint]
    }

    let minimumPointDistance: Float
    let maximumPointCount: Int
    private(set) var strokes: [SpatialStroke] = []
    private var activeStroke: ActiveStroke?

    init(minimumPointDistance: Float = 0.02, maximumPointCount: Int = 5_000) {
        self.minimumPointDistance = max(0.001, minimumPointDistance.isFinite ? minimumPointDistance : 0.02)
        self.maximumPointCount = max(2, maximumPointCount)
    }

    var pointCount: Int {
        strokes.reduce(0) { $0 + $1.points.count } + (activeStroke?.points.count ?? 0)
    }

    var isDrawing: Bool { activeStroke != nil }

    mutating func beginStroke(style: SpatialStrokeStyle) {
        if activeStroke != nil { endStroke() }
        activeStroke = ActiveStroke(style: style, points: [])
    }

    mutating func append(position: SIMD3<Float>) -> SpatialStrokeAppendResult {
        guard var activeStroke else { return .notDrawing }
        guard pointCount < maximumPointCount else { return .limitReached }
        guard let point = SpatialStrokePoint(position: position) else { return .rejectedInvalid }
        if let last = activeStroke.points.last,
           simd_distance(last.position, point.position) < minimumPointDistance {
            return .ignoredTooClose
        }
        activeStroke.points.append(point)
        self.activeStroke = activeStroke
        return .accepted
    }

    mutating func endStroke() {
        guard let activeStroke else { return }
        self.activeStroke = nil
        guard activeStroke.points.count >= 2 else { return }
        strokes.append(SpatialStroke(style: activeStroke.style, points: activeStroke.points))
    }

    mutating func undo() {
        activeStroke = nil
        if !strokes.isEmpty { strokes.removeLast() }
    }

    mutating func clear() {
        activeStroke = nil
        strokes.removeAll(keepingCapacity: true)
    }
}
