@preconcurrency import CoreLocation
import Foundation
import MapGrapherCore

/// 地図を開いた時に一度だけ測位し、常時追跡しません。
@MainActor
final class MapLocationAdapter: NSObject, MapLocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var pending: CheckedContinuation<MapLocationState, Never>?
    private var timeout: Task<Void, Never>?
    private var requestID: UUID?

    func requestCurrentLocation() async -> MapLocationState {
        if pending != nil { return .unavailable }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let activeManager = CLLocationManager()
                activeManager.delegate = self
                activeManager.desiredAccuracy = kCLLocationAccuracyBest
                manager = activeManager
                pending = continuation
                requestID = id
                if Task.isCancelled {
                    finish(.unavailable, matching: id)
                    return
                }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) }
                    catch { return }
                    self?.finish(.unavailable, matching: id)
                }
                switch activeManager.authorizationStatus {
                case .notDetermined:
                    activeManager.requestWhenInUseAuthorization()
                case .authorizedAlways, .authorizedWhenInUse:
                    activeManager.requestLocation()
                case .denied, .restricted:
                    finish(.permissionDenied)
                @unknown default:
                    finish(.unavailable)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.unavailable, matching: id) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let source = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in self?.authorizationChanged(source: source) }
    }

    private func authorizationChanged(source: ObjectIdentifier) {
        guard pending != nil, let manager, ObjectIdentifier(manager) == source else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            finish(.unavailable)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let source = ObjectIdentifier(manager)
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        let timestamp = location.timestamp
        Task { @MainActor [weak self] in
            self?.receive(latitude: latitude, longitude: longitude,
                          accuracy: accuracy, timestamp: timestamp, source: source)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let source = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in self?.finish(.unavailable, source: source) }
    }

    private func receive(latitude: Double, longitude: Double, accuracy: Double,
                         timestamp: Date, source: ObjectIdentifier) {
        guard pending != nil, let manager, ObjectIdentifier(manager) == source else { return }
        let age = Date().timeIntervalSince(timestamp)
        guard let point = GeoPoint(latitude: latitude, longitude: longitude),
              accuracy.isFinite, accuracy >= 0, age >= -2, age <= 10 else {
            finish(.invalid)
            return
        }
        if manager.accuracyAuthorization == .reducedAccuracy || accuracy > 25 {
            finish(.approximate(point))
        } else {
            finish(.ready(point))
        }
    }

    private func finish(_ state: MapLocationState, matching id: UUID? = nil,
                        source: ObjectIdentifier? = nil) {
        if let id, requestID != id { return }
        if let source, manager.map({ ObjectIdentifier($0) }) != source { return }
        guard let pending else { return }
        self.pending = nil
        requestID = nil
        timeout?.cancel()
        timeout = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        pending.resume(returning: state)
    }

}
