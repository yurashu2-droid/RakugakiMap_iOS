import MapGrapherCore
import SwiftUI

/// 写真詳細から開く描画導線。元写真はprivate loader経由で表示し、送信するのは透明PNGのみ。
@MainActor
struct AddRakugakiFlow: View {
    let photo: Photo
    let service: any ExistingPhotoRakugakiServing

    @Environment(\.dismiss) private var dismiss
    @State private var operationID = UUID()
    @State private var base: PreparedPostingImage?
    @State private var document: DrawingDocument?
    @State private var result: ExistingRakugakiSubmissionResult?
    @State private var error: Error?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultView(result)
                } else if let base {
                    VStack(spacing: 0) {
                        DrawingScreen(preparedImage: base, document: document,
                            onDocumentChange: { updated in
                                guard !isBusy else { return }
                                document = updated
                                error = nil
                            },
                            onSkip: { dismiss() },
                            onContinue: { Task { await submit() } })
                        if let error {
                            Text(error.localizedDescription)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding()
                        }
                    }
                    .overlay { if isBusy { ProgressView("投稿を確認しています") } }
                } else if let error {
                    ContentUnavailableView("写真を開けません", systemImage: "photo.badge.exclamationmark",
                                           description: Text(error.localizedDescription))
                    Button("再試行") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    ProgressView("写真を確認しています")
                }
            }
            .navigationTitle("ラクガキを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task(id: photo.id) { await load() }
        .onDisappear {
            if let base { service.discard(base: base) }
        }
        .accessibilityIdentifier("screen.existing-photo-rakugaki")
    }

    @ViewBuilder
    private func resultView(_ result: ExistingRakugakiSubmissionResult) -> some View {
        VStack(spacing: 20) {
            Image(systemName: result.state == .completed && result.approval != .rejected ?
                    "checkmark.circle.fill" :
                    "exclamationmark.circle.fill")
                .font(.system(size: 58))
                .accessibilityHidden(true)
            Text(resultTitle(result))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let error { Text(error.localizedDescription).font(.footnote) }
            if result.state == .outcomeUnknown || result.state == .retryWaiting ||
                result.state == .needsLogin {
                Button("同じ投稿を確認する") { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            }
            Button("閉じる") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("existing-rakugaki.result")
    }

    private func resultTitle(_ result: ExistingRakugakiSubmissionResult) -> String {
        if result.state == .completed {
            switch result.approval {
            case .pending: return "ラクガキを送信しました。写真の持ち主の承認待ちです"
            case .approved: return "ラクガキを公開しました"
            case .rejected: return "このラクガキは承認されていません"
            case nil: break
            }
        }
        if result.state == .needsCorrection {
            return "投稿を確認できません。画像を保持したまま確認が必要です"
        }
        return "投稿結果を確認中です"
    }

    private func load() async {
        guard !isBusy, base == nil else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let prepared = try await service.prepare(photo: photo)
            guard !Task.isCancelled else {
                service.discard(base: prepared)
                return
            }
            base = prepared
            document = DrawingDocument(pixelWidth: prepared.prepared.pixelWidth,
                                       pixelHeight: prepared.prepared.pixelHeight, strokes: [])
        } catch {
            self.error = error
        }
    }

    private func submit() async {
        guard !isBusy, let base, let document, !document.strokes.isEmpty else {
            error = AppFailure.validation("ラクガキを描いてから送信してください")
            return
        }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            result = try await service.submit(photo: photo, base: base,
                                              document: document, operationID: operationID)
        } catch {
            self.error = error
            // 失敗後も同じ操作IDと筆跡を保持して、同じ投稿として再確認する。
            let state: SubmissionState
            if let failure = error as? AppFailure {
                state = switch failure {
                case .forbidden, .notFound, .validation: .needsCorrection
                case .cancelled, .needsLogin: .needsLogin
                default: .outcomeUnknown
                }
            } else {
                state = .outcomeUnknown
            }
            result = ExistingRakugakiSubmissionResult(operationID: operationID,
                state: state, remoteRakugakiID: nil, approval: nil)
        }
    }
}
