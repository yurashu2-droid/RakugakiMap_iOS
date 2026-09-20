import SwiftUI
import UIKit

@MainActor
struct TraceExplorerScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var model: TraceExplorerModel
    let onSelect: (ARTrace) -> Void

    init(model: TraceExplorerModel, onSelect: @escaping (ARTrace) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onSelect = onSelect
    }

    var body: some View {
        List {
            if model.state == .ready && model.traces.isEmpty {
                ContentUnavailableView("近くにAR痕跡はありません", systemImage: "location.slash",
                                       description: Text("公開中のARが発見範囲に入ると表示します。"))
            }
            ForEach(model.traces) { trace in
                Button {
                    onSelect(trace)
                } label: {
                    HStack {
                        Image(systemName: "arkit")
                        Text("AR痕跡")
                        Spacer()
                        Text("約\(Int(trace.distanceM.rounded())) m")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("近くのAR")
        .overlay {
            if model.state != .ready && model.traces.isEmpty {
                ContentUnavailableView(message, systemImage: "location",
                                       description: Text("現地で正確な位置情報を確認します。"))
            }
        }
        .toolbar {
            if model.state == .permissionDenied {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() }
            else { model.stop() }
        }
    }

    private var message: String {
        switch model.state {
        case .idle, .locating: "位置を確認しています"
        case .permissionDenied: "位置情報の許可が必要です"
        case .preciseLocationRequired: "正確な位置情報が必要です"
        case .ready: "近くにAR痕跡はありません"
        case .unavailable: "AR痕跡を取得できませんでした"
        }
    }
}
