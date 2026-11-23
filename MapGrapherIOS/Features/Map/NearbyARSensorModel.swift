import Combine
import Foundation
import MapGrapherCore

/// 地図の「ARの気配メーター」。近くに公開中のARがあると、近さを4段階と向きで知らせる。
/// 正確な距離や座標は出さない（探す楽しみを残す。設計書の「距離帯と方向だけを表示」に合わせる）。
/// 使うのは今ある `get_nearby_ar_traces` と端末の位置・コンパスだけで、サーバーは変えていない。
@MainActor
final class NearbyARSensorModel: ObservableObject {
    @MainActor
    struct Services {
        let context: SessionContext
        let repository: any ARExperienceServing
        let location: any ARLocationProviding
        let heading: any HeadingProviding
        let session: any SessionProviding
    }

    /// 0は気配なし（メーターを出さない）。1〜4は近さで、4がいちばん近い。
    @Published private(set) var strength = 0
    /// 画面の上（端末の正面）を0度として、ARのある向き。右回りが正。向きが分からないときはnil。
    /// 真後ろをまたいでも矢印が遠回りしないよう、±180度で折り返さずに足し引きした値を持つ。
    @Published private(set) var arrowDegrees: Double?
    /// 見られる距離（そのARの解放半径）に入っているAR。入っていなければnil。
    @Published private(set) var openableTrace: ARTrace?
    private(set) var isRunning = false

    /// 段階や「見られる距離」の境目で、測位の誤差により表示がちらつかないようにする余裕
    static let hysteresisM = 6.0
    /// 向きの矢印を出し始める段階（100mより近い）
    static let arrowFromStrength = 2

    private let services: Services?
    private let clock: @Sendable () -> Date
    private var locationTask: Task<Void, Never>?
    private var headingTask: Task<Void, Never>?
    private var generation = UUID()
    private var traces: [ARTrace] = []
    private var point: GeoPoint?
    private var trackedID: UUID?
    private var trackedBearing: Double?
    private var strengthAnchorM: Double?
    private var headingDegrees: Double?
    private var lastGoodAt: Date?
    private var lastQueryAt: Date?
    private var lastQueryPoint: GeoPoint?

    /// servicesがnilのときは何もしない（ログイン前の試作表示やUIテスト）。
    init(services: Services?, clock: @escaping @Sendable () -> Date = Date.init) {
        self.services = services
        self.clock = clock
    }

    /// 位置もサーバーも使わず、決まった表示を出す。UIテストで見た目を確かめるためのもの。
    static func fixed(strength: Int, arrowDegrees: Double?,
                      openableTrace: ARTrace?) -> NearbyARSensorModel {
        let model = NearbyARSensorModel(services: nil)
        model.strength = strength
        model.arrowDegrees = arrowDegrees
        model.openableTrace = openableTrace
        return model
    }

    func start() {
        guard let services, !isRunning else { return }
        // 位置の許可を求める画面は、ここからは出さない。地図が現在地を取れたあとにだけ動かす。
        guard services.location.access == .allowed else { return }
        isRunning = true
        let token = UUID()
        generation = token
        let locationStream = services.location.updates()
        services.location.start()
        locationTask = Task { [weak self] in
            for await sample in locationStream {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                await self.receive(sample, token: token)
            }
        }
        let headingStream = services.heading.updates()
        services.heading.start()
        headingTask = Task { [weak self] in
            for await sample in headingStream {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.receive(sample)
            }
        }
    }

    func stop() {
        guard let services, isRunning else { return }
        isRunning = false
        generation = UUID()
        locationTask?.cancel()
        locationTask = nil
        headingTask?.cancel()
        headingTask = nil
        services.location.stop()
        services.heading.stop()
        traces = []
        point = nil
        headingDegrees = nil
        lastGoodAt = nil
        lastQueryAt = nil
        lastQueryPoint = nil
        clearReading()
    }

    private func receive(_ sample: LocationSample, token: UUID) async {
        guard let services else { return }
        guard await services.session.isCurrent(services.context) else {
            if generation == token { stop() }
            return
        }
        guard generation == token else { return }
        guard services.location.access == .allowed else { stop(); return }
        let now = clock()
        let age = now.timeIntervalSince(sample.timestamp)
        // AR画面の解放条件と同じ基準（10秒以内・精度25m以下）の測位だけを使う。
        guard (0...10).contains(age), sample.horizontalAccuracyM <= 25 else {
            // 使えない測位が続いたら、古い表示を残さない。
            if let lastGoodAt, now.timeIntervalSince(lastGoodAt) > 20 { clearReading() }
            return
        }
        lastGoodAt = now
        point = sample.point
        if shouldQuery(at: sample.point, now: now) {
            lastQueryAt = now
            lastQueryPoint = sample.point
            do {
                let result = try await services.repository.nearbyTraces(
                    at: sample.point, context: services.context)
                guard generation == token else { return }
                traces = result
            } catch {
                guard generation == token else { return }
                // 取得に失敗しても、前に分かっている分で続ける。
            }
        }
        recompute()
    }

    private func receive(_ sample: TrueHeadingSample) {
        // 向きの精度が粗いときは矢印を出さない。
        headingDegrees = sample.accuracyDegrees <= 45 ? sample.degrees : nil
        updateArrow()
    }

    /// 地図を開いている間じゅう動くので、サーバーへの問い合わせは間引く。
    /// 5秒以上あけ、20m以上動いたか、60秒たったときだけ問い合わせる。
    private func shouldQuery(at current: GeoPoint, now: Date) -> Bool {
        guard let lastQueryAt, let lastQueryPoint else { return true }
        let interval = now.timeIntervalSince(lastQueryAt)
        guard interval >= 5 else { return false }
        return interval >= 60 || ARScreenModel.distanceM(current, lastQueryPoint) >= 20
    }

    private func recompute() {
        guard let point else { clearReading(); return }
        var nearest: ARTrace?
        var nearestDistance = Double.infinity
        for trace in traces {
            let distance = ARScreenModel.distanceM(point, trace.location)
            // いま追っているARは、発見半径の境目で出たり消えたりしないよう少し余裕を持たせる。
            let margin = trace.id == trackedID ? Self.hysteresisM : 0
            guard distance <= trace.discoveryRadiusM + margin, distance < nearestDistance else { continue }
            nearest = trace
            nearestDistance = distance
        }
        guard let nearest, let band = TraceDistanceBand.classify(nearestDistance) else {
            clearReading()
            return
        }

        let raw = Self.strength(for: band)
        var next = strength
        if trackedID != nearest.id || strength == 0 {
            next = raw
            strengthAnchorM = nearestDistance
        } else if raw != strength,
                  abs(nearestDistance - (strengthAnchorM ?? nearestDistance)) >= Self.hysteresisM {
            // 段階が変わるのは、前に変わった距離から余裕の分だけ動いたときだけ。
            next = raw
            strengthAnchorM = nearestDistance
        }

        let wasOpenable = openableTrace?.id == nearest.id
        let limit = nearest.unlockRadiusM + (wasOpenable ? Self.hysteresisM : 0)
        let openable: ARTrace? = nearestDistance <= limit ? nearest : nil

        trackedID = nearest.id
        // すぐ近くでは、測位の誤差で向きがあてにならないので出さない。
        trackedBearing = nearestDistance >= 5
            ? TraceDirection.bearing(from: point, to: nearest.location) : nil
        if strength != next { strength = next }
        if openableTrace != openable { openableTrace = openable }
        updateArrow()
    }

    private func updateArrow() {
        guard strength >= Self.arrowFromStrength,
              let trackedBearing, let headingDegrees,
              let relative = TraceDirection.relativeBearing(
                targetBearingDegrees: trackedBearing, trueHeadingDegrees: headingDegrees) else {
            if arrowDegrees != nil { arrowDegrees = nil }
            return
        }
        guard let current = arrowDegrees else {
            arrowDegrees = relative
            return
        }
        // 前の角度から近い側の差だけ足す。2度より小さい揺れでは動かさない。
        var delta = (relative - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        guard abs(delta) >= 2 else { return }
        arrowDegrees = current + delta
    }

    private func clearReading() {
        trackedID = nil
        trackedBearing = nil
        strengthAnchorM = nil
        if strength != 0 { strength = 0 }
        if arrowDegrees != nil { arrowDegrees = nil }
        if openableTrace != nil { openableTrace = nil }
    }

    /// 距離帯（Coreの `TraceDistanceBand`）を、メーターの4段階に当てる。
    static func strength(for band: TraceDistanceBand) -> Int {
        switch band {
        case .far: return 1
        case .medium: return 2
        case .near: return 3
        case .immediate: return 4
        }
    }
}
