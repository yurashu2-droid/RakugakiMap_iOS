import SwiftUI
import UIKit

@MainActor
struct ARProbeScreen: View {
    let isUITesting: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var driver = ARSessionDriver()
    @State private var sharePayload: ARSharePayload?
    @State private var snapshotError: String?
    @State private var captureTask: Task<Void, Never>?
    @State private var captureGeneration = 0
    @State private var isCapturing = false

    init(isUITesting: Bool) {
        self.isUITesting = isUITesting
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("AR試作")
                .font(.title2.bold())

            if isUITesting {
                Text("UIテスト中はカメラを起動しません。")
            } else {
                if driver.isPrepared {
                    ARCanvasView(driver: driver)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("ARカメラ映像。床か壁をタップして配置")
                } else {
                    ContentUnavailableView(
                        "ARを開始する",
                        systemImage: "arkit",
                        description: Text("カメラを使い、床や壁に透過画像を1枚置きます。")
                    )
                    .frame(maxHeight: .infinity)
                }

                Text(driver.statusText)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ar.status")

                if let snapshotError {
                    Text(snapshotError)
                        .foregroundStyle(.red)
                }

                if driver.permissionDenied {
                    Button("設定を開く") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }

                if driver.isPrepared {
                    HStack {
                        Button("配置を解除") { driver.resetPlacement() }
                            .disabled(!driver.hasPlacement)
                        Spacer()
                        Button("写真を共有") { captureAndShare() }
                            .disabled(!driver.isRunning || isCapturing)
                    }
                    Button("ARを停止") {
                        cancelCapture()
                        driver.pause()
                    }
                } else if !driver.unsupported {
                    Button("ARを開始") {
                        snapshotError = nil
                        driver.start()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("戻る") {
                cancelCapture()
                driver.pause()
                dismiss()
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.ar-preview")
        .accessibilityLabel("AR試作")
        .sheet(item: $sharePayload) { payload in
            ARShareSheet(image: payload.image)
        }
        .onAppear {
            driver.setSceneActive(scenePhase == .active, cancelPending: scenePhase == .background)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelCapture()
            }
            driver.setSceneActive(phase == .active, cancelPending: phase == .background)
        }
        .onChange(of: driver.isRunning) { _, running in
            if !running {
                cancelCapture()
            }
        }
        .onDisappear {
            cancelCapture()
            driver.pause()
        }
    }

    private func captureAndShare() {
        guard !isCapturing, driver.isRunning else { return }
        isCapturing = true
        snapshotError = nil
        captureGeneration &+= 1
        let generation = captureGeneration
        captureTask = Task {
            defer {
                if generation == captureGeneration {
                    isCapturing = false
                    captureTask = nil
                }
            }
            do {
                let image = try await driver.snapshot()
                guard !Task.isCancelled,
                      generation == captureGeneration,
                      driver.isRunning,
                      scenePhase == .active else { return }
                sharePayload = ARSharePayload(image: image)
            } catch {
                guard !Task.isCancelled,
                      generation == captureGeneration,
                      driver.isRunning,
                      scenePhase == .active else { return }
                snapshotError = "写真を作成できませんでした。再試行してください。"
            }
        }
    }

    private func cancelCapture() {
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
    }
}

@MainActor
private struct ARSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

@MainActor
private struct ARShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
