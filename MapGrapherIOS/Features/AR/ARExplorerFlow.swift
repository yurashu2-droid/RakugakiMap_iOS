import SwiftUI
import MapGrapherCore

/// 地図から近傍ARの発見と現地表示へ進む実データ導線。
@MainActor
struct ARExplorerFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrace: ARTrace?

    let repository: any ARExperienceServing
    let assetLoader: any ARImageLoading
    let session: any SessionProviding
    let context: SessionContext

    var body: some View {
        NavigationStack {
            TraceExplorerScreen(
                model: TraceExplorerModel(context: context, repository: repository,
                                          location: ForegroundLocationProvider(), session: session)
            ) { trace in
                selectedTrace = trace
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedTrace) { trace in
            ARScreen(model: ARScreenModel(trace: trace, context: context,
                repository: repository, imageLoader: assetLoader,
                location: ForegroundLocationProvider(), session: session))
        }
    }
}
