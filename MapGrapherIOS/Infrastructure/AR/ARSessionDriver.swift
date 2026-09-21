import ARKit
import AVFoundation
import Combine
import RealityKit
import simd
import UIKit

@MainActor
final class ARSessionDriver: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var statusText = "開始するとカメラの使用許可を確認します。"
    @Published private(set) var isPrepared = false
    @Published private(set) var isRunning = false
    @Published private(set) var hasPlacement = false
    @Published private(set) var placementState: ARPlacementState = .scanning
    @Published private(set) var canCaptureWorldMap = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var unsupported = false

    private weak var arView: ARView?
    private var placement: AnchorEntity?
    private var placementSurfaceTransform: simd_float4x4?
    private var placementEditor: ARPlacementEditor?
    private var persistentAnchor: ARAnchor?
    private var wantsStart = false
    private var startGeneration = 0
    private var isSceneActive = true
    private var permissionWasGranted = false
    private var contentImage: UIImage?
    private var contentWidthM: Double = 1

    func setContent(image: UIImage, displayWidthM: Double) throws {
        guard let pixels = image.cgImage else { throw ARImagePlaneError.missingPixels }
        _ = try ARPlaneGeometry(pixelWidth: Double(pixels.width),
                                pixelHeight: Double(pixels.height),
                                displayWidthM: displayWidthM)
        resetPlacement()
        contentImage = image
        contentWidthM = displayWidthM
    }

    func clearContent() {
        resetPlacement()
        contentImage = nil
        contentWidthM = 1
    }

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
        guard isRunning, placementState != .locked, let arView else { return }
        guard let result = arView.raycast(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .any
        ).first,
              result.anchor is ARPlaneAnchor else {
            statusText = "面を探しています。端末をゆっくり動かしてから再試行してください。"
            return
        }

        do {
            let image = contentImage ?? ARImagePlaneFactory.makeFixtureImage()
            let model = try ARImagePlaneFactory.makeEntity(
                image: image, displayWidthM: contentWidthM)

            // 新しい板の準備ができてから古いanchorを除去し、常に1枚だけにする。
            resetPlacement()
            let worldTransform = standingTransform(for: result, in: arView)
            let anchor = AnchorEntity(world: worldTransform)
            anchor.addChild(model)
            arView.scene.addAnchor(anchor)
            placement = anchor
            placementSurfaceTransform = worldTransform
            let position = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
            placementEditor = ARPlacementEditor(initial: ARPlacement(
                position: position,
                yawRadians: 0,
                displayWidthM: contentWidthM
            )!)
            hasPlacement = true
            placementState = .editing
            statusText = "立体配置しました。ドラッグ・回転・拡大縮小して調整できます。"
        } catch {
            statusText = "透過画像を配置できませんでした。再試行してください。"
        }
    }

    func movePlacement(to point: CGPoint) {
        guard isRunning,
              let arView,
              var editor = placementEditor,
              editor.state == .editing,
              let result = arView.raycast(
                from: point,
                allowing: .existingPlaneGeometry,
                alignment: .any
              ).first,
              result.anchor is ARPlaneAnchor else {
            return
        }
        let surfaceTransform = standingTransform(for: result, in: arView)
        editor.move(to: SIMD3<Float>(
            surfaceTransform.columns.3.x,
            surfaceTransform.columns.3.y,
            surfaceTransform.columns.3.z
        ))
        placementEditor = editor
        placementSurfaceTransform = surfaceTransform
        applyPlacementTransform()
    }

    func scalePlacement(by factor: CGFloat) {
        guard factor.isFinite,
              factor > 0,
              var editor = placementEditor,
              editor.state == .editing,
              let anchor = placement else {
            return
        }
        editor.scale(by: Double(factor))
        do {
            let image = contentImage ?? ARImagePlaneFactory.makeFixtureImage()
            let model = try ARImagePlaneFactory.makeEntity(
                image: image,
                displayWidthM: editor.placement.displayWidthM
            )
            for child in anchor.children {
                child.removeFromParent()
            }
            anchor.addChild(model)
            placementEditor = editor
            contentWidthM = editor.placement.displayWidthM
        } catch {
            statusText = "大きさを変更できませんでした。"
        }
    }

    func rotatePlacement(by radians: CGFloat) {
        guard radians.isFinite,
              var editor = placementEditor,
              editor.state == .editing else {
            return
        }
        editor.rotate(by: Float(radians))
        placementEditor = editor
        applyPlacementTransform()
    }

    func lockPlacement() {
        guard var editor = placementEditor,
              editor.state == .editing else {
            return
        }
        editor.lock()
        placementEditor = editor
        placementState = .locked
        statusText = "この位置に固定しました。公開前なら配置をやり直せます。"
    }

    func unlockPlacement() {
        guard var editor = placementEditor,
              editor.state == .locked else {
            return
        }
        editor.unlock()
        placementEditor = editor
        placementState = .editing
        statusText = "配置を再調整できます。"
    }

    func capturePersistentPackage() async throws -> PersistentARPackage {
        guard placementState == .locked,
              let editor = placementEditor else {
            throw ARWorldMapCaptureError.placementNotLocked
        }
        guard canCaptureWorldMap else {
            throw ARWorldMapCaptureError.mappingNotReady
        }
        guard isRunning,
              isSceneActive,
              let arView,
              let placement else {
            throw ARWorldMapCaptureError.sessionUnavailable
        }

        let generation = startGeneration
        let sessionIdentifier = ObjectIdentifier(arView.session)
        if let persistentAnchor {
            arView.session.remove(anchor: persistentAnchor)
        }
        let anchorName = "rakugaki:\(UUID().uuidString.lowercased())"
        let anchor = ARAnchor(
            name: anchorName,
            transform: placement.transformMatrix(relativeTo: nil)
        )
        arView.session.add(anchor: anchor)
        persistentAnchor = anchor

        do {
            let data = try await ARWorldMapCaptureRequest.captureArchive(
                from: arView.session,
                requiredAnchorName: anchorName
            )
            guard !Task.isCancelled,
                  generation == startGeneration,
                  isRunning,
                  isSceneActive,
                  self.arView === arView,
                  isCurrentSession(sessionIdentifier) else {
                throw ARWorldMapCaptureError.cancelled
            }
            guard let package = PersistentARPackage(
                data: data,
                anchorName: anchorName,
                displayWidthM: editor.placement.displayWidthM
            ) else {
                throw ARWorldMapCaptureError.packageInvalid
            }
            statusText = "空間データを保存しました。公開できます。"
            return package
        } catch {
            arView.session.remove(anchor: anchor)
            if persistentAnchor === anchor {
                persistentAnchor = nil
            }
            unlockPlacement()
            statusText = "空間データを保存できませんでした。周囲を映して再試行してください。"
            throw error
        }
    }

    func resetPlacement() {
        if let persistentAnchor, let arView {
            arView.session.remove(anchor: persistentAnchor)
        }
        persistentAnchor = nil
        placement?.removeFromParent()
        placement = nil
        placementSurfaceTransform = nil
        placementEditor = nil
        hasPlacement = false
        placementState = .scanning
    }

    private func applyPlacementTransform() {
        guard let anchor = placement,
              let surfaceTransform = placementSurfaceTransform,
              let editor = placementEditor else {
            return
        }
        let yaw = simd_float4x4(simd_quatf(
            angle: editor.placement.yawRadians,
            axis: SIMD3<Float>(0, 1, 0)
        ))
        anchor.transform.matrix = simd_mul(surfaceTransform, yaw)
    }

    private func standingTransform(
        for result: ARRaycastResult,
        in view: ARView
    ) -> simd_float4x4 {
        let position = SIMD3<Float>(
            result.worldTransform.columns.3.x,
            result.worldTransform.columns.3.y,
            result.worldTransform.columns.3.z
        )
        let cameraColumn = view.cameraTransform.matrix.columns.3
        let cameraPosition = SIMD3<Float>(
            cameraColumn.x,
            cameraColumn.y,
            cameraColumn.z
        )
        let up = SIMD3<Float>(0, 1, 0)
        var forward: SIMD3<Float>

        if let plane = result.anchor as? ARPlaneAnchor,
           plane.alignment == .vertical {
            let normalColumn = result.worldTransform.columns.1
            forward = SIMD3<Float>(normalColumn.x, 0, normalColumn.z)
            if simd_length_squared(forward) > 0.0001 {
                forward = simd_normalize(forward)
                let towardCamera = cameraPosition - position
                if simd_dot(forward, towardCamera) < 0 {
                    forward *= -1
                }
            }
        } else {
            forward = SIMD3<Float>(
                cameraPosition.x - position.x,
                0,
                cameraPosition.z - position.z
            )
        }

        if simd_length_squared(forward) <= 0.0001 {
            forward = SIMD3<Float>(0, 0, 1)
        } else {
            forward = simd_normalize(forward)
        }
        let right = simd_normalize(simd_cross(up, forward))
        let correctedForward = simd_normalize(simd_cross(right, up))
        return simd_float4x4(columns: (
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(up.x, up.y, up.z, 0),
            SIMD4<Float>(correctedForward.x, correctedForward.y, correctedForward.z, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        ))
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
        canCaptureWorldMap = false
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

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let identifier = ObjectIdentifier(session)
        let ready = frame.worldMappingStatus == .extending || frame.worldMappingStatus == .mapped
        Task { @MainActor [weak self] in
            guard let self,
                  self.isRunning,
                  self.isCurrentSession(identifier) else {
                return
            }
            self.canCaptureWorldMap = ready
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
