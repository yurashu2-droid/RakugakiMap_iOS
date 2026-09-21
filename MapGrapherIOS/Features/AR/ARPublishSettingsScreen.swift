import Foundation
import MapGrapherCore
import SwiftUI
import UIKit

/// 承認済みラクガキを現地で立体配置し、空間データと公開RPCを一度の操作で完了する。
@MainActor
struct ARPublishSettingsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    let photoID: UUID
    let rakugakiID: UUID
    let imageAsset: AssetReference
    let context: SessionContext
    let repository: any ARExperienceServing
    let imageLoader: any ARImageLoading

    @StateObject private var driver = ARSessionDriver()
    @StateObject private var publishModel = ARPersistentPublishModel()
    @State private var unlockRadiusM = 50.0
    @State private var discoveryRadiusM = 150.0
    @State private var imageLoading = true
    @State private var setupError: String?
    @State private var leaseGranted = false
    @State private var leaseRequestInFlight = false
    @State private var activeLeaseID: UUID?
    @State private var prepareGeneration = UUID()
    private let lease: ARCameraLease

    init(photoID: UUID, rakugakiID: UUID, imageAsset: AssetReference,
         context: SessionContext, repository: any ARExperienceServing,
         imageLoader: any ARImageLoading, lease: ARCameraLease = .shared) {
        self.photoID = photoID
        self.rakugakiID = rakugakiID
        self.imageAsset = imageAsset
        self.context = context
        self.repository = repository
        self.imageLoader = imageLoader
        self.lease = lease
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            cameraContent
            Text(statusText)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if driver.permissionDenied {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
            if setupError != nil {
                Button("再試行") {
                    setupError = nil
                    Task { await prepare() }
                }
                .buttonStyle(.borderedProminent)
            }

            if publishModel.state != .published && driver.placementState == .editing {
                Button("この位置に固定") { driver.lockPlacement() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ar.publish.lock")
            } else if publishModel.state != .published && driver.placementState == .locked {
                HStack {
                    Button("配置をやり直す") {
                        publishModel.cancelSession()
                        driver.unlockPlacement()
                    }
                    .buttonStyle(.bordered)

                    Button(publishButtonTitle) {
                        Task { await publish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPublish)
                    .accessibilityIdentifier("ar.publish.commit")
                }
            }

            DisclosureGroup("公開範囲") {
                LabeledContent("解放半径", value: "\(Int(unlockRadiusM)) m")
                Slider(value: $unlockRadiusM, in: 10...200, step: 10)
                LabeledContent("発見半径", value: "\(Int(discoveryRadiusM)) m")
                Slider(value: $discoveryRadiusM, in: max(30, unlockRadiusM)...500, step: 10)
            }
            .disabled(isWorking)

            if publishModel.state == .published {
                Label("この場所にARを公開しました", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .navigationTitle("現地にARを置く")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onChange(of: unlockRadiusM) { _, value in
            discoveryRadiusM = max(discoveryRadiusM, value)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await prepare() }
            } else {
                closeResources()
            }
        }
        .onDisappear { closeResources() }
    }

    @ViewBuilder
    private var cameraContent: some View {
        if leaseGranted && driver.isPrepared {
            ARCanvasView(driver: driver)
                .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("ARカメラ。床または壁をタップしてラクガキを配置")
        } else {
            ContentUnavailableView(
                "ARを準備しています",
                systemImage: "arkit",
                description: Text(setupError ?? "承認済みラクガキとカメラを読み込んでいます。")
            )
            .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        }
    }

    private var isWorking: Bool {
        publishModel.state == .capturing || publishModel.state == .uploading
    }

    private var canPublish: Bool {
        guard !isWorking, publishModel.state != .published else { return false }
        if publishModel.hasCapturedPackage { return true }
        return driver.placementState == .locked && driver.canCaptureWorldMap
    }

    private var publishButtonTitle: String {
        if publishModel.hasCapturedPackage { return "公開を再試行" }
        switch publishModel.state {
        case .capturing: return "空間を保存中…"
        case .uploading: return "公開中…"
        default: return "この場所にAR公開"
        }
    }

    private var statusText: String {
        if let setupError { return setupError }
        switch publishModel.state {
        case .capturing: return "周囲と配置を空間データへ保存しています。"
        case .uploading: return "ARを安全にアップロードしています。"
        case .published: return "同じ場所で周囲を映すと、この配置を復元できます。"
        case .failed(let retryable):
            return retryable
                ? "通信に失敗しました。配置データを保持しているため、そのまま再試行できます。"
                : "空間を保存できませんでした。周囲を映して配置を確認してください。"
        case .scanning:
            if driver.placementState == .locked && !driver.canCaptureWorldMap {
                return "固定できました。周囲をゆっくり映して空間の認識を安定させてください。"
            }
            return driver.statusText
        }
    }

    private func prepare() async {
        guard scenePhase == .active, imageLoading, !leaseRequestInFlight,
              activeLeaseID == nil else { return }
        setupError = nil
        leaseRequestInFlight = true
        let generation = prepareGeneration
        let requestID = UUID()
        guard await lease.acquire(requestID) else {
            leaseRequestInFlight = false
            setupError = "別の画面がカメラを使用しています。閉じてから再試行してください。"
            return
        }
        guard generation == prepareGeneration, scenePhase == .active else {
            await lease.release(requestID)
            leaseRequestInFlight = false
            return
        }
        do {
            let image = try await imageLoader.load(
                asset: imageAsset,
                targetPixelSize: CGSize(width: 4096, height: 4096),
                context: context
            )
            try Task.checkCancellation()
            guard generation == prepareGeneration, scenePhase == .active else {
                throw AppFailure.cancelled
            }
            try driver.setContent(image: image, displayWidthM: 1)
            activeLeaseID = requestID
            leaseGranted = true
            imageLoading = false
            leaseRequestInFlight = false
            driver.start()
        } catch {
            await lease.release(requestID)
            leaseRequestInFlight = false
            leaseGranted = false
            setupError = "承認済みラクガキを読み込めませんでした。通信状態を確認してください。"
        }
    }

    private func publish() async {
        await publishModel.publish(
            capture: { try await driver.capturePersistentPackage() },
            upload: { package in
                try await repository.publishPersistent(
                    package: package,
                    photoID: photoID,
                    rakugakiID: rakugakiID,
                    unlockRadiusM: unlockRadiusM,
                    discoveryRadiusM: discoveryRadiusM,
                    fallbackAltitudeM: nil,
                    fallbackHeadingDeg: nil,
                    context: context
                )
            }
        )
    }

    private func closeResources() {
        prepareGeneration = UUID()
        publishModel.cancelSession()
        driver.pause()
        driver.clearContent()
        leaseRequestInFlight = false
        leaseGranted = false
        imageLoading = true
        guard let id = activeLeaseID else { return }
        activeLeaseID = nil
        Task { await lease.release(id) }
    }
}
