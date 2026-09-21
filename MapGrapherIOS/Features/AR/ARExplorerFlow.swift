import SwiftUI
import MapGrapherCore

/// 地図から近傍ARの発見と現地表示へ進む実データ導線。
@MainActor
struct ARExplorerFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrace: ARTrace?
    @State private var targetError: String?

    let repository: any ARExperienceServing
    let assetLoader: any ARImageLoading
    let session: any SessionProviding
    let context: SessionContext
    let targetPhotoID: UUID?

    init(repository: any ARExperienceServing, assetLoader: any ARImageLoading,
         session: any SessionProviding, context: SessionContext,
         targetPhotoID: UUID? = nil) {
        self.repository = repository; self.assetLoader = assetLoader
        self.session = session; self.context = context
        self.targetPhotoID = targetPhotoID
    }

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
        .task(id: targetPhotoID) {
            guard let targetPhotoID else { return }
            do {
                let experience = try await repository.experience(
                    photoID: targetPhotoID, context: context)
                guard !Task.isCancelled, await session.isCurrent(context),
                      let trace = ARTrace(
                        id: experience.id, photoID: experience.photoID,
                        location: experience.location,
                        unlockRadiusM: experience.unlockRadiusM,
                        discoveryRadiusM: experience.discoveryRadiusM,
                        distanceM: 0, createdAt: Date(), anchorType: experience.anchorType
                      ) else { return }
                selectedTrace = trace
            } catch {
                guard !Task.isCancelled else { return }
                targetError = "この写真のARはまだ公開されていないか、表示できません。"
            }
        }
        .alert("ARを開けません", isPresented: Binding(
            get: { targetError != nil },
            set: { if !$0 { targetError = nil } }
        )) {
            Button("閉じる", role: .cancel) { targetError = nil }
        } message: {
            Text(targetError ?? "")
        }
    }
}
