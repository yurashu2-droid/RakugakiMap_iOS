import Combine
import Foundation
import MapGrapherCore
import UIKit

@MainActor
protocol ARImageLoading {
    func load(asset: AssetReference, targetPixelSize: CGSize,
              context: SessionContext) async throws -> UIImage
}

extension PrivateAssetLoader: ARImageLoading {}

enum ARViewingState: Equatable {
    case idle
    case locating
    case locationDenied
    case locationImprecise
    case locationUnavailable
    case outsideRadius
    case checking
    case loadingImage
    case ready
    case unavailable
}

/// 新鮮な連続測位で解放してから、権限と素材を再取得する。
@MainActor
final class ARScreenModel: ObservableObject {
    @Published private(set) var state: ARViewingState = .idle
    @Published private(set) var image: UIImage?
    @Published private(set) var experience: ArExperience?

    let trace: ARTrace
    private let context: SessionContext
    private let repository: any ARExperienceServing
    private let imageLoader: any ARImageLoading
    private let location: any ARLocationProviding
    private let session: any SessionProviding
    private let clock: @Sendable () -> Date
    private let locationTimeout: Duration
    private var task: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()

    init(trace: ARTrace, context: SessionContext,
         repository: any ARExperienceServing, imageLoader: any ARImageLoading,
         location: any ARLocationProviding, session: any SessionProviding,
         clock: @escaping @Sendable () -> Date = Date.init,
         locationTimeout: Duration = .seconds(15)) {
        self.trace = trace; self.context = context; self.repository = repository
        self.imageLoader = imageLoader; self.location = location
        self.session = session; self.clock = clock
        self.locationTimeout = locationTimeout
    }

    func start() {
        stop()
        if location.access == .denied { state = .locationDenied; return }
        if location.access == .reducedAccuracy { state = .locationImprecise; return }
        let token = generation
        let stream = location.updates()
        location.start()
        state = .locating
        task = Task { [weak self] in
            guard let self else { return }
            var gate = RevealGate()
            for await sample in stream {
                guard !Task.isCancelled, self.generation == token else { return }
                guard await self.session.isCurrent(self.context) else {
                    self.stop(); return
                }
                if self.location.access == .denied {
                    self.state = .locationDenied; self.stopLocationOnly(); return
                }
                if self.location.access == .reducedAccuracy {
                    gate = RevealGate()
                    self.state = .locationImprecise
                    continue
                }
                let distance = Self.distanceM(sample.point, self.trace.location)
                let unlocked = gate.ingest(distanceM: distance,
                    accuracyM: sample.horizontalAccuracyM, timestamp: sample.timestamp,
                    now: self.clock(), radiusM: self.trace.unlockRadiusM)
                if !unlocked {
                    self.state = distance > self.trace.unlockRadiusM ? .outsideRadius : .locating
                    continue
                }
                await self.resolve(sample: sample, token: token)
                return
            }
            guard !Task.isCancelled, self.generation == token else { return }
            self.state = self.location.access == .denied ? .locationDenied : .unavailable
        }
        locationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: self?.locationTimeout ?? .seconds(15)) }
            catch { return }
            guard let self, self.generation == token, self.state == .locating else { return }
            self.state = .locationUnavailable
            self.stopLocationOnly()
        }
    }

    func retryLocation() { start() }

    func refresh() async {
        guard state == .ready else { return }
        let token = generation
        image = nil
        experience = nil
        state = .checking
        // 再入場・前景復帰では必ず2点の連続測位からやり直す。
        guard generation == token else { return }
        start()
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        location.stop()
        image = nil
        experience = nil
        state = .idle
    }

    private func stopLocationOnly() {
        task?.cancel()
        task = nil
        location.stop()
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
    }

    private func resolve(sample: LocationSample, token: UUID) async {
        state = .checking
        do {
            let fresh = try await repository.experience(photoID: trace.photoID, context: context)
            try await check(token)
            let age = clock().timeIntervalSince(sample.timestamp)
            guard (0...10).contains(age), sample.horizontalAccuracyM <= 25,
                  Self.distanceM(sample.point, fresh.location) <= fresh.unlockRadiusM else {
                state = .outsideRadius; start(); return
            }
            guard fresh.id == trace.id, fresh.anchorType == .localPlane else {
                throw AppFailure.notFound
            }
            state = .loadingImage
            let loaded = try await imageLoader.load(asset: fresh.asset,
                targetPixelSize: CGSize(width: 4096, height: 4096), context: context)
            try await check(token)
            experience = fresh
            image = loaded
            state = .ready
            stopLocationOnly()
            refreshTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard let self, self.generation == token else { return }
                self.start()
            }
        } catch {
            guard generation == token else { return }
            image = nil
            experience = nil
            state = .unavailable
            stopLocationOnly()
        }
    }

    private func check(_ token: UUID) async throws {
        try Task.checkCancellation()
        guard generation == token, await session.isCurrent(context) else {
            throw AppFailure.cancelled
        }
    }

    static func distanceM(_ lhs: GeoPoint, _ rhs: GeoPoint) -> Double {
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}
