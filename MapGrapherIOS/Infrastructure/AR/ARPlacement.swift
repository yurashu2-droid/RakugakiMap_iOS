import Foundation
import simd

enum ARPlacementLimits {
    static let widthRange = 0.1...10.0
}

enum ARPlacementState: Equatable, Sendable {
    case scanning
    case editing
    case locked
}

/// 現在のARセッション内で編集中の配置値。
/// 永続化時は名前付きARAnchorのtransformと最終表示幅へ変換する。
struct ARPlacement: Equatable, Sendable {
    let position: SIMD3<Float>
    let yawRadians: Float
    let displayWidthM: Double

    init?(position: SIMD3<Float>, yawRadians: Float, displayWidthM: Double) {
        guard position.x.isFinite,
              position.y.isFinite,
              position.z.isFinite,
              yawRadians.isFinite,
              displayWidthM.isFinite else {
            return nil
        }
        self.position = position
        self.yawRadians = Self.normalized(yawRadians)
        self.displayWidthM = min(
            ARPlacementLimits.widthRange.upperBound,
            max(ARPlacementLimits.widthRange.lowerBound, displayWidthM)
        )
    }

    func scaled(by factor: Double) -> Self {
        guard factor.isFinite, factor > 0,
              let placement = Self(
                position: position,
                yawRadians: yawRadians,
                displayWidthM: displayWidthM * factor
              ) else {
            return self
        }
        return placement
    }

    func rotated(by delta: Float) -> Self {
        guard delta.isFinite,
              let placement = Self(
                position: position,
                yawRadians: yawRadians + delta,
                displayWidthM: displayWidthM
              ) else {
            return self
        }
        return placement
    }

    private static func normalized(_ angle: Float) -> Float {
        let fullTurn = Float.pi * 2
        var value = (angle + .pi).truncatingRemainder(dividingBy: fullTurn)
        if value < 0 {
            value += fullTurn
        }
        return value - .pi
    }
}

struct ARPlacementEditor: Equatable, Sendable {
    private(set) var placement: ARPlacement
    private(set) var state: ARPlacementState = .editing

    init(initial: ARPlacement) {
        placement = initial
    }

    mutating func move(to position: SIMD3<Float>) {
        guard state == .editing,
              let next = ARPlacement(
                position: position,
                yawRadians: placement.yawRadians,
                displayWidthM: placement.displayWidthM
              ) else {
            return
        }
        placement = next
    }

    mutating func scale(by factor: Double) {
        guard state == .editing else { return }
        placement = placement.scaled(by: factor)
    }

    mutating func rotate(by delta: Float) {
        guard state == .editing else { return }
        placement = placement.rotated(by: delta)
    }

    mutating func lock() {
        guard state == .editing else { return }
        state = .locked
    }

    mutating func unlock() {
        guard state == .locked else { return }
        state = .editing
    }
}
