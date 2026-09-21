import simd

/// ARKitカメラ姿勢から、空間ストロークへ記録するペン先を決める。
enum SpatialPenTipMode: String, CaseIterable, Equatable, Sendable {
    case cameraBody
    case cameraForward

    static let forwardDistanceM: Float = 0.3

    func position(cameraTransform: simd_float4x4) -> SIMD3<Float>? {
        guard Self.isFinite(cameraTransform) else { return nil }

        let worldPoint: SIMD4<Float>
        switch self {
        case .cameraBody:
            worldPoint = cameraTransform.columns.3
        case .cameraForward:
            worldPoint = simd_mul(
                cameraTransform,
                SIMD4<Float>(0, 0, -Self.forwardDistanceM, 1)
            )
        }

        let position = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        return position
    }

    private static func isFinite(_ transform: simd_float4x4) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where !transform[column][row].isFinite {
                return false
            }
        }
        return true
    }
}
