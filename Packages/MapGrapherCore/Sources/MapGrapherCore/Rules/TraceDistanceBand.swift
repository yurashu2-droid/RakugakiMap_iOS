import Foundation

public enum TraceDistanceBand: String, Codable, Sendable {
    case immediate
    case near
    case medium
    case far

    public static func classify(_ distanceM: Double) -> Self? {
        guard distanceM.isFinite, distanceM >= 0 else { return nil }
        switch distanceM {
        case ..<15: return .immediate
        case ..<50: return .near
        case ..<100: return .medium
        default: return .far
        }
    }
}
