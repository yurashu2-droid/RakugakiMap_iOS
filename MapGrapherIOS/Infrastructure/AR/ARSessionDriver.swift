import ARKit
import AVFoundation
import Combine
import RealityKit
import UIKit

@MainActor
final class ARSessionDriver: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var statusText = "開始するとカメラの使用許可を確認します。"
    @Published private(set) var isPrepared = false
    @Published private(set) var isRunning = false
    @Published private(set) var hasPlacement = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var unsupported = false

    private weak var arView: ARView?
    private var placement: AnchorEntity?
    private var wantsStart = false
    private var startGeneration = 0
    private var isSceneActive = true
    private var permissionWasGranted = false

    private func isCurrentSession(_ identifier: ObjectIdentifier) -> Bool {
        guard let arView else { return false }
        return ObjectIdentifier(arView.session) == identifier
    }

    func setSceneActive(_ active: Bool, cancelPending: Bool = true) {
        isSceneActive = active
        if !active, (cancelPending || isPrepared), (wantsStart || isPrepared) {
            pause()
        } else if active, wantsStart, permissionWasGranted {
            finishPermission(granted: true, generation: startGeneration)
        }
    }

    func attach(view: ARView) {
        arView = view
        view.session.delegate = self
        view.session.delegateQueue = .main
        if wantsStart, isPrepared {
            runSession(on: view)
        }
    }

    func detach(view: ARView) {
        guard arView === view else { return }
        pause()
    }

    /// カメラ許可の応答が遅れても、退出後の開始要求を再利用しない。
    func start() {
        guard isSceneActive else {
            statusText = "画面に戻ってからARを開始してください。"
            return
        }
        startGeneration &+= 1
        let generation = startGeneration
        wantsStart = true
        permissionWasGranted = false
        permissionDenied = false
        unsupported = false

        guard ARWorldTrackingConfiguration.isSupported else {
            wantsStart = false
            unsupported = true
            statusText = "この端末はARの平面追跡に対応していません。戻る操作をご利用ください。"
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            finishPermission(granted: true, generation: generation)
        case .notDetermined:
            statusText = "カメラの許可を確認しています。"
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                self?.finishPermission(granted: granted, generation: generation)
            }
        case .denied, .restricted:
            finishPermission(granted: false, generation: generation)
        @unknown default:
            finishPermission(granted: false, generation: generation)
        }
    }

    private func finishPermission(granted: Bool, generation: Int) {
        guard generation == startGeneration, wantsStart else { return }
        guard granted else {
            wantsStart = false
            permissionDenied = true
            statusText = "カメラが許可されていません。設定で許可してから再開してください。"
            return
        }

        if !isSceneActive {
            permissionWasGranted = true
            statusText = "画面に戻るとARを開始します。"
            return
        }

        permissionWasGranted = false
        permissionDenied = false
        statusText = "端末をゆっくり動かして床や壁を探し、画面をタップしてください。"
        isPrepared = true
        if let arView {
            runSession(on: arView)
        }
    }

    private func runSession(on view: ARView) {
        guard wantsStart, !isRunning else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func place(at point: CGPoint) {
        guard isRunning, let arView else { return }
        guard let result = arView.raycast(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .any
        ).first,
              let planeAnchor = result.anchor as? ARPlaneAnchor else {
            statusText = "面を探しています。端末をゆっくり動かしてから再試行してください。"
            return
        }

        do {
            let image = ARImagePlaneFactory.makeFixtureImage()
            let model = try ARImagePlaneFactory.makeEntity(image: image)
            model.position.y = 0.002

            // 新しい板の準備ができてから古いanchorを除去し、常に1枚だけにする。
            resetPlacement()
            // ARPlaneAnchorのXZ面・Y法線を採用し、交点の位置だけraycastへ合わせる。
            var worldTransform = planeAnchor.transform
            worldTransform.columns.3 = result.worldTransform.columns.3
            let anchor = AnchorEntity(world: worldTransform)
            anchor.addChild(model)
            arView.scene.addAnchor(anchor)
            placement = anchor
            hasPlacement = true
            statusText = "配置しました。別の面をタップすると再配置できます。"
        } catch {
            statusText = "透過画像を配置できませんでした。再試行してください。"
        }
    }

    func resetPlacement() {
        placement?.removeFromParent()
        placement = nil
        hasPlacement = false
    }

    func pause() {
        startGeneration &+= 1
        wantsStart = false
        permissionWasGranted = false
        resetPlacement()
        if let arView {
            arView.session.delegate = nil
            arView.session.pause()
        }
        arView = nil
        isRunning = false
        isPrepared = false
        statusText = "ARを停止しました。再開時は面を探して配置し直してください。"
    }

    func snapshot() async throws -> UIImage {
        guard isRunning, isSceneActive, let arView else {
            throw ARSnapshotError.imageUnavailable
        }
        let generation = startGeneration
        let sessionIdentifier = ObjectIdentifier(arView.session)
        let image = try await ARSnapshotWriter.capture(from: arView)
        guard !Task.isCancelled,
              generation == startGeneration,
              isRunning,
              isSceneActive,
              self.arView === arView,
              isCurrentSession(sessionIdentifier) else {
            throw ARSnapshotError.cancelled
        }
        return image
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let identifier = ObjectIdentifier(session)
        let message: String
        switch camera.trackingState {
        case .normal:
            message = "追跡できています。床や壁をタップして配置できます。"
        case .notAvailable:
            message = "追跡できません。周囲を明るくして再試行してください。"
        case .limited(let reason):
            switch reason {
            case .initializing:
                message = "追跡を準備しています。端末をゆっくり動かしてください。"
            case .excessiveMotion:
                message = "動きが速すぎます。端末をゆっくり動かしてください。"
            case .insufficientFeatures:
                message = "特徴が少ない面です。模様のある床や壁へ向けてください。"
            case .relocalizing:
                message = "位置を復元しています。周囲をゆっくり映してください。"
            @unknown default:
                message = "追跡が制限されています。端末をゆっくり動かしてください。"
            }
        }
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, self.isCurrentSession(identifier) else { return }
            self.statusText = message
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        let identifier = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, self.isCurrentSession(identifier) else { return }
            self.pause()
            self.statusText = "ARが中断されました。再開してから配置し直してください。"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        let identifier = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self, self.isPrepared, self.isCurrentSession(identifier) else { return }
            self.statusText = "ARの中断が終わりました。再開してから配置し直してください。"
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let identifier = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self, self.isPrepared, self.isCurrentSession(identifier) else { return }
            self.pause()
            self.statusText = "ARを継続できませんでした。再開してお試しください。"
        }
    }
}
