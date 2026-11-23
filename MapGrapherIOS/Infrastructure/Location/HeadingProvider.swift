@preconcurrency import CoreLocation
import Foundation

struct TrueHeadingSample: Sendable {
    let degrees: Double
    let accuracyDegrees: Double
    let timestamp: Date
}

/// 端末の向き（真北基準）を流す。テストでは偽物に差し替える
@MainActor
protocol HeadingProviding {
    func updates() -> AsyncStream<TrueHeadingSample>
    func start()
    func stop()
}

@MainActor
final class HeadingProvider: NSObject, CLLocationManagerDelegate, HeadingProviding {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<TrueHeadingSample>.Continuation?
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
        // 真北の向きは、同じマネージャーで位置の更新も動いているときだけ有効な値になる
        // （磁北との差を出すのに現在地が要る。AppleのCLHeading.trueHeadingの説明による）。
        // 向きの補正に使うだけなので、粗い精度と広い間隔で足りる。
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 500
    }

    func updates() -> AsyncStream<TrueHeadingSample> {
        continuation?.finish()
        let pair = AsyncStream.makeStream(of: TrueHeadingSample.self)
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        guard !isRunning, CLLocationManager.headingAvailable() else { return }
        isRunning = true
        // 位置の許可を求める画面は、ここからは出さない。許可済みのときだけ位置の更新も動かす。
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined, .denied, .restricted:
            break
        @unknown default:
            break
        }
        manager.startUpdatingHeading()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        continuation?.finish()
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let degrees = heading.trueHeading
        let accuracy = heading.headingAccuracy
        let timestamp = heading.timestamp
        Task { @MainActor [weak self] in
            self?.receive(degrees: degrees, accuracy: accuracy, timestamp: timestamp)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 位置が一時的に取れなくても、向きの更新は続ける。真北が出ない間のサンプルはreceiveで捨てる。
    }

    private func receive(degrees: Double, accuracy: Double, timestamp: Date) {
        guard isRunning,
              accuracy >= 0,
              degrees.isFinite,
              (0..<360).contains(degrees) else { return }
        continuation?.yield(TrueHeadingSample(degrees: degrees,
                                              accuracyDegrees: accuracy,
                                              timestamp: timestamp))
    }
}
