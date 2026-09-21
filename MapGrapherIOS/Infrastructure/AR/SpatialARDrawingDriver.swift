import ARKit
import AVFoundation
import Combine
import RealityKit
import simd
import UIKit

@MainActor
final class SpatialARDrawingDriver: NSObject, ObservableObject, ARSessionDelegate {
    enum Status: Equatable, Sendable {
        case idle
        case requestingCamera
        case ready
        case trackingLimited(String)
        case cameraDenied
        case cameraBusy
        case unsupported
        case pointLimitReached
        case interrupted
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var isDrawing = false
    @Published private(set) var pointCount = 0
    @Published private(set) var completedStrokeCount = 0

    private let lease: ARCameraLease
    private var recorder: SpatialStrokeRecorder
    private weak var arView: ARView?
    private var completedAnchors: [AnchorEntity] = []
    private var activeAnchor: AnchorEntity?
    private var lastAcceptedPosition: SIMD3<Float>?
    private var activeStyle: SpatialStrokeStyle?
    private var activeLeaseID: UUID?
    private var requestGeneration = 0
    private var wantsStart = false

    init(
        lease: ARCameraLease = .shared,
        minimumPointDistance: Float = 0.02,
        maximumPointCount: Int = 5_000
    ) {
        self.lease = lease
        recorder = SpatialStrokeRecorder(
            minimumPointDistance: minimumPointDistance,
            maximumPointCount: maximumPointCount
        )
        super.init()
    }

    var canUndo: Bool { completedStrokeCount > 0 && !isDrawing }
    var canClear: Bool { (pointCount > 0 || completedStrokeCount > 0) && !isDrawing }

    func attach(view: ARView) {
        arView = view
        view.session.delegate = self
        view.session.delegateQueue = .main
        runSessionIfReady()
    }

    func detach(view: ARView) {
        guard arView === view else { return }
        stop(resetDrawing: true)
        arView = nil
    }

    func start() {
        guard !isRunning, activeLeaseID == nil else { return }
        requestGeneration &+= 1
        let generation = requestGeneration
        wantsStart = true

        guard ARWorldTrackingConfiguration.isSupported else {
            wantsStart = false
            status = .unsupported
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            acquireCamera(generation: generation)
        case .notDetermined:
            status = .requestingCamera
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self, generation == self.requestGeneration, self.wantsStart else { return }
                if granted { self.acquireCamera(generation: generation) }
                else { self.wantsStart = false; self.status = .cameraDenied }
            }
        case .denied, .restricted:
            wantsStart = false
            status = .cameraDenied
        @unknown default:
            wantsStart = false
            status = .cameraDenied
        }
    }

    func beginStroke(style: SpatialStrokeStyle) {
        guard isRunning, !isDrawing else { return }
        recorder.beginStroke(style: style)
        activeStyle = style
        lastAcceptedPosition = nil
        let anchor = AnchorEntity(world: .zero)
        arView?.scene.addAnchor(anchor)
        activeAnchor = anchor
        isDrawing = true
    }

    func endStroke() {
        guard isDrawing else { return }
        let oldCount = recorder.strokes.count
        recorder.endStroke()
        if recorder.strokes.count > oldCount, let activeAnchor {
            completedAnchors.append(activeAnchor)
        } else {
            activeAnchor?.removeFromParent()
        }
        activeAnchor = nil
        lastAcceptedPosition = nil
        activeStyle = nil
        isDrawing = false
        synchronizeCounts()
    }

    func undo() {
        guard !isDrawing else { return }
        recorder.undo()
        completedAnchors.popLast()?.removeFromParent()
        synchronizeCounts()
        clearPointLimitStatusIfPossible()
    }

    func clear() {
        guard !isDrawing else { return }
        recorder.clear()
        completedAnchors.forEach { $0.removeFromParent() }
        completedAnchors.removeAll(keepingCapacity: true)
        activeAnchor?.removeFromParent()
        activeAnchor = nil
        lastAcceptedPosition = nil
        activeStyle = nil
        synchronizeCounts()
        clearPointLimitStatusIfPossible()
    }

    func stop(resetDrawing: Bool) {
        requestGeneration &+= 1
        wantsStart = false
        if isDrawing { endStroke() }
        if resetDrawing { clear() }
        if let arView {
            arView.session.delegate = nil
            arView.session.pause()
        }
        isRunning = false
        if let leaseID = activeLeaseID {
            activeLeaseID = nil
            Task { await lease.release(leaseID) }
        }
        if status != .cameraDenied && status != .unsupported {
            status = .idle
        }
    }

    private func acquireCamera(generation: Int) {
        status = .requestingCamera
        let leaseID = UUID()
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.lease.acquire(leaseID)
            guard generation == self.requestGeneration, self.wantsStart else {
                if granted { await self.lease.release(leaseID) }
                return
            }
            guard granted else {
                self.wantsStart = false
                self.status = .cameraBusy
                return
            }
            self.activeLeaseID = leaseID
            self.runSessionIfReady()
        }
    }

    private func runSessionIfReady() {
        guard wantsStart, activeLeaseID != nil, !isRunning, let arView else { return }
        arView.session.delegate = self
        arView.session.delegateQueue = .main
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        status = .trackingLimited("空間を認識しています。端末をゆっくり動かしてください。")
    }

    private func ingest(position: SIMD3<Float>) {
        guard isDrawing else { return }
        switch recorder.append(position: position) {
        case .accepted:
            if let start = lastAcceptedPosition,
               let style = activeStyle,
               let anchor = activeAnchor,
               let geometry = SpatialStrokeSegmentGeometry(
                    start: start,
                    end: position,
                    radius: style.widthM * 0.5
               ) {
                anchor.addChild(makeSegment(geometry: geometry, color: style.color))
            }
            lastAcceptedPosition = position
            synchronizeCounts()
        case .limitReached:
            endStroke()
            status = .pointLimitReached
        case .notDrawing, .ignoredTooClose, .rejectedInvalid:
            break
        }
    }

    private func makeSegment(
        geometry: SpatialStrokeSegmentGeometry,
        color: SpatialBrushColor
    ) -> ModelEntity {
        let mesh: MeshResource
        if #available(iOS 18.0, *) {
            mesh = MeshResource.generateCylinder(
                height: geometry.length,
                radius: geometry.radius
            )
        } else {
            // iOS 17では角を半径分丸めた細長いboxを使い、円柱と同じ安全な外寸にする。
            mesh = MeshResource.generateBox(
                size: SIMD3<Float>(
                    geometry.radius * 2,
                    geometry.length,
                    geometry.radius * 2
                ),
                cornerRadius: geometry.radius
            )
        }
        let material = SimpleMaterial(color: color.uiColor, roughness: 0.32, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = geometry.center
        entity.orientation = geometry.orientation
        return entity
    }

    private func synchronizeCounts() {
        pointCount = recorder.pointCount
        completedStrokeCount = recorder.strokes.count
    }

    private func clearPointLimitStatusIfPossible() {
        if isRunning, status == .pointLimitReached, pointCount < recorder.maximumPointCount {
            status = .ready
        }
    }

    private func isCurrentSession(_ identifier: ObjectIdentifier) -> Bool {
        guard let arView else { return false }
        return ObjectIdentifier(arView.session) == identifier
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let identifier = ObjectIdentifier(session)
        let column = frame.camera.transform.columns.3
        let position = SIMD3<Float>(column.x, column.y, column.z)
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, self.isCurrentSession(identifier) else { return }
            self.ingest(position: position)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let identifier = ObjectIdentifier(session)
        let nextStatus: Status
        switch camera.trackingState {
        case .normal:
            nextStatus = .ready
        case .notAvailable:
            nextStatus = .trackingLimited("追跡できません。周囲を明るくしてください。")
        case .limited(let reason):
            switch reason {
            case .initializing:
                nextStatus = .trackingLimited("空間を認識しています。端末をゆっくり動かしてください。")
            case .excessiveMotion:
                nextStatus = .trackingLimited("動きが速すぎます。端末をゆっくり動かしてください。")
            case .insufficientFeatures:
                nextStatus = .trackingLimited("特徴が少ない場所です。模様のある周囲へ向けてください。")
            case .relocalizing:
                nextStatus = .trackingLimited("位置を復元しています。周囲をゆっくり映してください。")
            @unknown default:
                nextStatus = .trackingLimited("追跡を準備しています。")
            }
        }
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, self.isCurrentSession(identifier),
                  self.status != .pointLimitReached else { return }
            self.status = nextStatus
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        let identifier = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentSession(identifier) else { return }
            self.stop(resetDrawing: true)
            self.status = .interrupted
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let identifier = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentSession(identifier) else { return }
            self.stop(resetDrawing: true)
            self.status = .failed
        }
    }
}

private extension SpatialBrushColor {
    var uiColor: UIColor {
        switch self {
        case .coral: UIColor(red: 0.96, green: 0.35, blue: 0.28, alpha: 1)
        case .cyan: UIColor(red: 0.16, green: 0.82, blue: 0.92, alpha: 1)
        case .yellow: UIColor(red: 1, green: 0.82, blue: 0.18, alpha: 1)
        case .white: .white
        }
    }
}
