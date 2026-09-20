@preconcurrency import CoreLocation
import MapGrapherCore

/// 地図・現地探索の表示中だけ位置を更新する。権限は利用者が操作を始めた時に要求する。
@MainActor
final class ForegroundLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<LocationSample>.Continuation?
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracyAuthorization: CLAccuracyAuthorization { manager.accuracyAuthorization }

    func updates() -> AsyncStream<LocationSample> {
        continuation?.finish()
        let pair = AsyncStream.makeStream(of: LocationSample.self)
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        continuation?.finish()
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            continuation?.finish()
            continuation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning else { return }
        for location in locations {
            guard let point = GeoPoint(latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude),
                  let sample = LocationSample(point: point,
                                              horizontalAccuracyM: location.horizontalAccuracy,
                                              timestamp: location.timestamp) else { continue }
            continuation?.yield(sample)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的な測位失敗は次のサンプルを待つ。権限変化は専用callbackで扱う。
    }
}
