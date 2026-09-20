import PhotosUI
import SwiftUI

@MainActor
struct CaptureScreen: View {
    let isUITesting: Bool
    let isBusy: Bool
    let error: PostingFlowError?
    let onImport: (Data, String) async -> Void
    let onUseFixture: () async -> Void

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                VStack(spacing: AppSpacing.medium) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(AppColors.coral)
                        .accessibilityHidden(true)
                    Text("posting.capture.title")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .multilineTextAlignment(.center)
                    Text("posting.capture.detail")
                        .font(.body)
                        .foregroundStyle(AppColors.ink.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppSpacing.medium) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("posting.capture.choose", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                    .accessibilityIdentifier("posting.capture.photo-picker")

                    Text("posting.capture.camera-note")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.ink.opacity(0.70))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isUITesting {
                    Button {
                        Task { await onUseFixture() }
                    } label: {
                        Label("posting.capture.test-fixture", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .accessibilityIdentifier("posting.capture.test-fixture")
                }

                if isBusy {
                    ProgressView("posting.capture.preparing")
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("posting.capture.loading")
                }

                if let error {
                    PostingErrorView(error: error)
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.large)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.posting.capture")
        .accessibilityLabel(Text("posting.capture.title"))
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    let data = try await item.loadTransferable(type: Data.self) ?? Data()
                    await onImport(data, "photo-library")
                } catch {
                    await onImport(Data(), "photo-library")
                }
                selectedItem = nil
            }
        }
    }
}

@MainActor
struct PostingErrorView: View {
    let error: PostingFlowError

    var body: some View {
        Label(error.titleKey, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(AppColors.coral)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.medium)
            .background(AppColors.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("posting.error")
    }
}

private extension PostingFlowError {
    var titleKey: LocalizedStringKey {
        switch self {
        case .invalidImage:
            "posting.error.invalid-image"
        case .imageTooLarge:
            "posting.error.image-too-large"
        case .dimensionsTooLarge:
            "posting.error.dimensions-too-large"
        case .preparingFailed:
            "posting.error.preparing"
        case .invalidDraft:
            "posting.error.invalid-draft"
        case .saveFailed:
            "posting.error.save"
        case .submissionFailed:
            "posting.error.submission"
        }
    }
}
