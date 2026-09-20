import SwiftUI

@MainActor
struct AlbumDetailScreen: View {
    let album: AlbumSummary
    private let service: any SocialProfileUIService
    @StateObject private var model: AlbumDetailScreenModel
    @State private var photoID = ""
    @State private var photoToRemove: AlbumPhoto?
    @State private var showsDeleteDialog = false

    init(
        album: AlbumSummary,
        service: any SocialProfileUIService = FakeSocialProfileUIService()
    ) {
        self.album = album
        self.service = service
        _model = StateObject(wrappedValue: AlbumDetailScreenModel(albumID: album.id, service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                SocialPrototypeNotice(dataMode: service.dataMode)

                Group {
                    if album.description.isEmpty {
                        Text(AppStrings.albumDetail)
                    } else {
                        Text(album.description)
                    }
                }
                .font(.body)
                .foregroundStyle(AppColors.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

                addPhotoSection

                LoadStateView(
                    state: model.state,
                    emptyMessage: AppStrings.albumEmptyPhotos,
                    errorMessage: SocialUIMessage.errorKey(for: model.error),
                    retry: reload
                ) {
                    photoList
                }

                Button(AppStrings.albumDelete, role: .destructive) {
                    showsDeleteDialog = true
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
                .accessibilityIdentifier("album.delete")

                if model.didCompleteAction {
                    SocialActionNotice(dataMode: service.dataMode)
                }
                SocialActionError(error: model.error)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
        .confirmationDialog(
            AppStrings.albumRemoveConfirm,
            isPresented: Binding(
                get: { photoToRemove != nil },
                set: { if !$0 { photoToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let photoToRemove {
                Button(AppStrings.albumRemovePhoto, role: .destructive) {
                    Task { await model.removePhoto(photoToRemove) }
                }
            }
            Button("posting.close.cancel", role: .cancel) {}
        }
        .confirmationDialog(
            AppStrings.albumDeleteConfirm,
            isPresented: $showsDeleteDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.albumDelete, role: .destructive) {
                Task { await model.deleteAlbum() }
            }
            Button("posting.close.cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("screen.album-detail")
    }

    private var addPhotoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(AppStrings.albumAddPhoto)
                .font(.headline)
            HStack(spacing: AppSpacing.small) {
                TextField(AppStrings.albumPhotoIDPlaceholder, text: $photoID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("album.photo-id")

                Button {
                    guard let id = UUID(uuidString: photoID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        return
                    }
                    Task {
                        await model.addPhoto(photoID: id)
                        if model.error == nil { photoID = "" }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .frame(width: 48, height: 48)
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking || UUID(uuidString: photoID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                .accessibilityLabel(AppStrings.albumAddPhoto)
                .accessibilityIdentifier("album.add-photo")
            }
        }
    }

    private var photoList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ForEach(model.photos) { photo in
                HStack(spacing: AppSpacing.medium) {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(photo.title)
                            .font(.headline)
                        Text(photo.photoID.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.ink.opacity(0.70))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: AppSpacing.small)
                    Button {
                        photoToRemove = photo
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(AppStrings.albumRemovePhoto)
                    .accessibilityIdentifier("album.remove-photo.\(photo.id.uuidString)")
                }
                .padding(AppSpacing.medium)
                .background(AppColors.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }
}
