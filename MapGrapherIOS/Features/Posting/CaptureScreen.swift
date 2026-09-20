import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct CaptureScreen: View {
    let isUITesting: Bool
    let isBusy: Bool
    let error: PostingFlowError?
    let onImport: (Data, String) async -> Void
    let onUseFixture: () async -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var showsCamera = false

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
                    Button {
                        showsCamera = true
                    } label: {
                        Label("posting.capture.camera", systemImage: "camera")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    .accessibilityIdentifier("posting.capture.camera")

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
        .sheet(isPresented: $showsCamera) {
            PostingCameraPicker(isPresented: $showsCamera) { data in
                Task { await onImport(data, "camera.jpg") }
            }
            .ignoresSafeArea()
        }
    }
}

@MainActor
private struct PostingCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency UIImagePickerControllerDelegate,
                             @preconcurrency UINavigationControllerDelegate {
        private var isPresented: Binding<Bool>
        private let onCapture: (Data) -> Void

        init(isPresented: Binding<Bool>, onCapture: @escaping (Data) -> Void) {
            self.isPresented = isPresented
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }
            isPresented.wrappedValue = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented.wrappedValue = false
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
