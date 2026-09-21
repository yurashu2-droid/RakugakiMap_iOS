import ARKit
import CoreLocation
import MapGrapherCore

enum ARGeoTrackingAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable
    case unsupported
}

@MainActor
protocol ARGeoTrackingAdvising {
    func availability(at point: GeoPoint) async -> ARGeoTrackingAvailability
}

@MainActor
struct ARGeoTrackingAdvisor: ARGeoTrackingAdvising {
    func availability(at point: GeoPoint) async -> ARGeoTrackingAvailability {
        guard ARGeoTrackingConfiguration.isSupported else { return .unsupported }
        let coordinate = CLLocationCoordinate2D(
            latitude: point.latitude, longitude: point.longitude)
        return await withCheckedContinuation { continuation in
            ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { available, _ in
                continuation.resume(returning: available ? .available : .unavailable)
            }
        }
    }
}
