import Foundation
import MapGrapherCore
import SwiftUI

/// 公開RPCへ渡す5引数を明示して、承認待ちを公開成功と表示しない。
@MainActor
struct ARPublishSettingsScreen: View {
    let photoID: UUID
    let rakugakiID: UUID
    let context: SessionContext
    let repository: any ARExperienceServing

    @State private var unlockRadiusM = 50.0
    @State private var discoveryRadiusM = 150.0
    @State private var displayWidthM = 1.0
    @State private var isPublishing = false
    @State private var published: ArExperience?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("現地での解放") {
                LabeledContent("解放半径", value: "\(Int(unlockRadiusM)) m")
                Slider(value: $unlockRadiusM, in: 10...200, step: 10)
                LabeledContent("発見半径", value: "\(Int(discoveryRadiusM)) m")
                Slider(value: $discoveryRadiusM, in: max(30, unlockRadiusM)...500, step: 10)
            }
            Section("表示") {
                LabeledContent("描画の幅", value: String(format: "%.1f m", displayWidthM))
                Slider(value: $displayWidthM, in: 0.1...10, step: 0.1)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            if published != nil {
                Text("ARを公開しました。現地での確認はまだ必要です。")
                    .foregroundStyle(.green)
            }
            Button("承認済みラクガキをAR公開") {
                Task { await publish() }
            }
            .disabled(isPublishing)
        }
        .navigationTitle("AR公開設定")
        .onChange(of: unlockRadiusM) { _, value in
            discoveryRadiusM = max(discoveryRadiusM, value)
        }
    }

    private func publish() async {
        guard !isPublishing else { return }
        isPublishing = true
        errorText = nil
        published = nil
        defer { isPublishing = false }
        do {
            published = try await repository.publish(photoID: photoID,
                rakugakiID: rakugakiID, unlockRadiusM: unlockRadiusM,
                discoveryRadiusM: discoveryRadiusM,
                displayWidthM: displayWidthM, context: context)
        } catch {
            errorText = "公開できませんでした。写真の所有権とラクガキの承認状態を確認してください。"
        }
    }
}
