@preconcurrency import CoreLocation
import Foundation

struct TrueHeadingSample: Sendable {
    let degrees: Double
    let accuracyDegrees: Double
    let timestamp: Date
}

@MainActor
final class HeadingProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<TrueHeadingSample>.Continuation?
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
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
        manager.startUpdatingHeading()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingHeading()
        continuation?.finish()
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard isRunning,
              heading.headingAccuracy >= 0,
              heading.trueHeading.isFinite,
              (0..<360).contains(heading.trueHeading) else { return }
        continuation?.yield(TrueHeadingSample(degrees: heading.trueHeading,
                                              accuracyDegrees: heading.headingAccuracy,
                                              timestamp: heading.timestamp))
    }
}
