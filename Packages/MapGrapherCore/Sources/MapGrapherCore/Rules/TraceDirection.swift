import Foundation

public enum TraceDirection {
    /// 真北から時計回りの方位。両地点が同一なら0度を返すため、呼び出し側で距離を先に判定する。
    public static func bearing(from origin: GeoPoint, to target: GeoPoint) -> Double {
        let latitude1 = origin.latitude * .pi / 180
        let latitude2 = target.latitude * .pi / 180
        let longitudeDifference = (target.longitude - origin.longitude) * .pi / 180
        let east = sin(longitudeDifference) * cos(latitude2)
        let north = cos(latitude1) * sin(latitude2)
            - sin(latitude1) * cos(latitude2) * cos(longitudeDifference)
        let degrees = atan2(east, north) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 端末の真北headingに対する目標方向。右は正、左は負。
    public static func relativeBearing(targetBearingDegrees: Double, trueHeadingDegrees: Double) -> Double? {
        guard targetBearingDegrees.isFinite, trueHeadingDegrees.isFinite,
              (0..<360).contains(trueHeadingDegrees) else { return nil }
        let target = (targetBearingDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return (target - trueHeadingDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}
