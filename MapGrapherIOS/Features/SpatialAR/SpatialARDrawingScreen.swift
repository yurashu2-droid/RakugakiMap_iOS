import SwiftUI
import UIKit

@MainActor
struct SpatialARDrawingScreen: View {
    let isUITesting: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var driver = SpatialARDrawingDriver()
    @State private var selectedColor: SpatialBrushColor = .coral
    @State private var selectedWidthM: Float = 0.03
    @State private var isPressingDraw = false

    var body: some View {
        ZStack {
            canvas
                .ignoresSafeArea()

            if driver.penTipMode == .cameraForward {
                forwardSight
            }

            VStack(spacing: AppSpacing.medium) {
                header
                Spacer()
                statusCard
                recoveryAction
                penTipControls
                brushControls
                actionBar
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
        }
        .background(Color.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.spatial-ar-drawing")
        .accessibilityLabel("空間に描く")
        .onAppear {
            guard !isUITesting, scenePhase == .active else { return }
            driver.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isUITesting else { return }
            finishDrawing()
            if phase == .active { driver.start() }
            else { driver.stop(resetDrawing: true) }
        }
        .onDisappear {
            finishDrawing()
            driver.stop(resetDrawing: true)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        if isUITesting {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.18), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(.white.opacity(0.2))
            }
        } else {
            SpatialARCanvasView(driver: driver)
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("空間に描く")
                    .font(.title2.bold())
                Text(penTipDescription)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("閉じる")
            .accessibilityIdentifier("spatial-ar.close.button")
        }
    }

    private var forwardSight: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 34, height: 34)
            Circle()
                .fill(AppColors.coral)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 48, height: 1)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1, height: 48)
        }
        .shadow(color: .black.opacity(0.65), radius: 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("前方30センチのペン先")
        .accessibilityIdentifier("spatial-ar.forward-sight")
    }

    private var penTipControls: some View {
        HStack(spacing: AppSpacing.small) {
            penTipButton(
                mode: .cameraBody,
                title: "端末位置",
                symbol: "iphone",
                identifier: "spatial-ar.pen.camera-body"
            )
            penTipButton(
                mode: .cameraForward,
                title: "前方30cm",
                symbol: "scope",
                identifier: "spatial-ar.pen.camera-forward"
            )
        }
        .padding(AppSpacing.small)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func penTipButton(
        mode: SpatialPenTipMode,
        title: String,
        symbol: String,
        identifier: String
    ) -> some View {
        Button {
            driver.setPenTipMode(mode)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(driver.penTipMode == mode ? AppColors.coral : .white)
        .disabled(isPressingDraw)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(driver.penTipMode == mode ? .isSelected : [])
    }

    private var statusCard: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: statusSymbol)
            Text(isUITesting ? "UIテスト用プレビュー" : statusText)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(driver.pointCount)点")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.medium)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("spatial-ar.status")
    }

    @ViewBuilder
    private var recoveryAction: some View {
        switch driver.status {
        case .cameraDenied:
            Button("設定でカメラを許可") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.coral)
        case .cameraBusy, .interrupted, .failed:
            Button("ARを再試行") { driver.start() }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.coral)
        default:
            EmptyView()
        }
    }

    private var brushControls: some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                ForEach(SpatialBrushColor.allCases, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 30, height: 30)
                            .padding(5)
                            .background(.black.opacity(0.28), in: Circle())
                            .overlay {
                                Circle().stroke(
                                    selectedColor == color ? Color.white : Color.white.opacity(0.25),
                                    lineWidth: selectedColor == color ? 3 : 1
                                )
                            }
                    }
                    .disabled(isPressingDraw)
                    .accessibilityLabel(color.accessibilityName)
                    .accessibilityIdentifier("spatial-ar.color.\(color.rawValue)")
                    .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                }
            }

            HStack(spacing: AppSpacing.small) {
                widthButton(value: 0.01, title: "細")
                widthButton(value: 0.03, title: "中")
                widthButton(value: 0.06, title: "太")
            }
        }
        .padding(AppSpacing.medium)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func widthButton(value: Float, title: String) -> some View {
        Button {
            selectedWidthM = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(selectedWidthM == value ? AppColors.coral : .white)
        .disabled(isPressingDraw)
        .accessibilityLabel("線の太さ\(title)")
        .accessibilityIdentifier("spatial-ar.width.\(String(format: "%.2f", value))")
        .accessibilityAddTraits(selectedWidthM == value ? .isSelected : [])
    }

    private var actionBar: some View {
        HStack(spacing: AppSpacing.medium) {
            Button {
                driver.undo()
            } label: {
                Label("戻す", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!driver.canUndo)
            .accessibilityLabel("1画戻す")
            .accessibilityIdentifier("spatial-ar.undo.button")

            drawButton

            Button {
                driver.clear()
            } label: {
                Label("全消去", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!driver.canClear)
            .accessibilityLabel("すべて消す")
            .accessibilityIdentifier("spatial-ar.clear.button")
        }
    }

    private var drawButton: some View {
        Button(action: {}) {
            Label(isPressingDraw ? "描画中" : "押したまま描く", systemImage: "pencil.tip.crop.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.coral)
        .disabled(!isUITesting && !driver.isRunning)
        .accessibilityIdentifier("spatial-ar.draw.button")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startDrawingIfNeeded() }
                .onEnded { _ in finishDrawing() }
        )
    }

    private var statusText: String {
        switch driver.status {
        case .idle: "ARを準備しています。"
        case .requestingCamera: "カメラの利用を確認しています。"
        case .ready: "準備完了。押したまま端末を動かしてください。"
        case .trackingLimited(let message): message
        case .cameraDenied: "カメラが許可されていません。設定から許可してください。"
        case .cameraBusy: "別の画面がカメラを使用中です。閉じてから再試行してください。"
        case .unsupported: "この端末は空間AR描画に対応していません。"
        case .pointLimitReached: "安全のため5,000点で停止しました。不要な線を消してください。"
        case .interrupted: "ARが中断されました。画面を開き直してください。"
        case .failed: "ARを継続できませんでした。画面を開き直してください。"
        }
    }

    private var penTipDescription: String {
        switch driver.penTipMode {
        case .cameraBody:
            "端末の位置をペン先にして、押したまま動かします"
        case .cameraForward:
            "画面中央の30cm先をペン先にして、向きを動かします"
        }
    }

    private var statusSymbol: String {
        switch driver.status {
        case .ready: "checkmark.circle.fill"
        case .cameraDenied, .cameraBusy, .unsupported, .pointLimitReached, .interrupted, .failed:
            "exclamationmark.triangle.fill"
        default: "arkit"
        }
    }

    private func startDrawingIfNeeded() {
        guard !isUITesting, !isPressingDraw,
              let style = SpatialStrokeStyle(color: selectedColor, widthM: selectedWidthM) else { return }
        isPressingDraw = true
        driver.beginStroke(style: style)
    }

    private func finishDrawing() {
        guard isPressingDraw else { return }
        isPressingDraw = false
        driver.endStroke()
    }

    private func close() {
        finishDrawing()
        driver.stop(resetDrawing: true)
        dismiss()
    }
}

private extension SpatialBrushColor {
    var swiftUIColor: Color {
        switch self {
        case .coral: AppColors.coral
        case .cyan: .cyan
        case .yellow: .yellow
        case .white: .white
        }
    }

    var accessibilityName: String {
        switch self {
        case .coral: "コーラル"
        case .cyan: "シアン"
        case .yellow: "黄色"
        case .white: "白"
        }
    }
}
