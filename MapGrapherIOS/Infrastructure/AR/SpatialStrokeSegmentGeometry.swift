import Foundation
import simd

/// RealityKitのY軸方向の円柱を、2点を結ぶ空間線分へ変換する純粋な幾何情報。
struct SpatialStrokeSegmentGeometry: Equatable, Sendable {
    let center: SIMD3<Float>
    let length: Float
    let radius: Float
    let orientation: simd_quatf

    init?(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float) {
        guard Self.isFinite(start), Self.isFinite(end),
              radius.isFinite, radius > 0 else { return nil }

        let delta = end - start
        let length = simd_length(delta)
        guard length.isFinite, length > 0.000_001 else { return nil }

        let direction = delta / length
        let yAxis = SIMD3<Float>(0, 1, 0)
        let dot = simd_dot(yAxis, direction)
        let orientation: simd_quatf
        if dot > 0.999_999 {
            orientation = simd_quatf(angle: 0, axis: yAxis)
        } else if dot < -0.999_999 {
            orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let vector = SIMD4<Float>(simd_cross(yAxis, direction), 1 + dot)
            orientation = simd_quatf(vector: simd_normalize(vector))
        }

        self.center = (start + end) * 0.5
        self.length = length
        self.radius = radius
        self.orientation = orientation
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
