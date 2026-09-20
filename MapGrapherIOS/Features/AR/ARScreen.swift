import SwiftUI
import UIKit

@MainActor
struct ARScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ARScreenModel
    @StateObject private var driver = ARSessionDriver()
    @State private var leaseGranted = false
    @State private var leaseRequestInFlight = false
    @State private var activeLeaseID: UUID?
    private let lease: ARCameraLease

    init(model: ARScreenModel, lease: ARCameraLease = .shared) {
        _model = StateObject(wrappedValue: model)
        self.lease = lease
    }

    var body: some View {
        VStack(spacing: 12) {
            if model.state == .ready && driver.isPrepared && leaseGranted {
                ARCanvasView(driver: driver)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("ARカメラ。床または壁をタップして配置")
            } else {
                ContentUnavailableView("現地のAR", systemImage: "arkit",
                                       description: Text(message))
                    .frame(maxHeight: .infinity)
            }
            Text(model.state == .ready ? driver.statusText : message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.state == .locationDenied || driver.permissionDenied {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
            if model.state == .ready && !leaseGranted {
                Button("カメラを再試行") { activateAR() }
            }
            Button("戻る") { close() }
        }
        .padding()
        .onAppear { model.start() }
        .onDisappear { closeResources() }
        .onChange(of: model.state) { _, state in
            if state == .ready { activateAR() }
            else { driver.pause(); driver.clearContent(); releaseLease() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() }
            else { closeResources() }
        }
    }

    private var message: String {
        switch model.state {
        case .idle, .locating: "現地で位置を確認しています。位置情報を許可してください。"
        case .locationDenied: "位置情報が許可されていません。設定で許可してください。"
        case .locationImprecise: "正確な位置情報を許可してから再試行してください。"
        case .outsideRadius: "ARの解放地点へ近づいてください。"
        case .checking: "閲覧権限とARの公開状態を確認しています。"
        case .loadingImage: "承認済みの画像を安全に読み込んでいます。"
        case .ready: leaseGranted ? "床または壁をタップして配置してください。" : "別のカメラ利用の終了を待っています。"
        case .unavailable: "ARを表示できません。公開状態または通信を確認して戻ってください。"
        }
    }

    private func activateAR() {
        guard model.state == .ready, let image = model.image,
              let experience = model.experience, scenePhase == .active,
              !leaseRequestInFlight, activeLeaseID == nil else { return }
        leaseRequestInFlight = true
        let requestID = UUID()
        Task {
            guard await lease.acquire(requestID) else {
                leaseRequestInFlight = false; leaseGranted = false; return
            }
            guard model.state == .ready, scenePhase == .active,
                  leaseRequestInFlight else {
                await lease.release(requestID)
                leaseRequestInFlight = false
                return
            }
            do {
                try driver.setContent(image: image, displayWidthM: experience.displayWidthM)
                activeLeaseID = requestID
                leaseRequestInFlight = false
                leaseGranted = true
                driver.start()
            } catch {
                await lease.release(requestID)
                leaseRequestInFlight = false
                leaseGranted = false
            }
        }
    }

    private func releaseLease() {
        leaseRequestInFlight = false
        leaseGranted = false
        guard let id = activeLeaseID else { return }
        activeLeaseID = nil
        Task { await lease.release(id) }
    }

    private func closeResources() {
        model.stop()
        driver.pause()
        driver.clearContent()
        releaseLease()
    }

    private func close() {
        closeResources()
        dismiss()
    }
}
