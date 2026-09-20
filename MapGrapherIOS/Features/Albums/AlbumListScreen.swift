import Foundation
import SwiftUI

@MainActor
struct AlbumListScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: AlbumListScreenModel
    @State private var showsCreateSheet = false
    @State private var albumToDelete: AlbumSummary?

    init(service: any SocialProfileUIService = FakeSocialProfileUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: AlbumListScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    SocialPrototypeNotice(dataMode: service.dataMode)

                    Button {
                        showsCreateSheet = true
                    } label: {
                        Label(AppStrings.albumCreate, systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("album.create")

                    LoadStateView(
                        state: model.state,
                        emptyMessage: AppStrings.albumEmpty,
                        errorMessage: SocialUIMessage.errorKey(for: model.error),
                        retry: reload
                    ) {
                        albumList
                    }

                    if model.didCompleteAction {
                        SocialActionNotice(dataMode: service.dataMode)
                    }
                    SocialActionError(error: model.error)
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.medium)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.albumTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
            }
            .sheet(isPresented: $showsCreateSheet) {
                AlbumCreateScreen(service: service) { _ in
                    model.markCreated()
                    Task { await model.load() }
                    showsCreateSheet = false
                }
            }
            .confirmationDialog(
                AppStrings.albumDeleteConfirm,
                item: $albumToDelete
            ) { album in
                Button(AppStrings.albumDelete, role: .destructive) {
                    Task { await model.delete(album: album) }
                }
                Button("posting.close.cancel", role: .cancel) {}
            }
        }
        .accessibilityIdentifier("screen.albums")
    }

    private var albumList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ForEach(model.albums) { album in
                HStack(spacing: AppSpacing.small) {
                    NavigationLink {
                        AlbumDetailScreen(album: album, service: service)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(album.title)
                                .font(.headline)
                            if !album.description.isEmpty {
                                Text(album.description)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.ink.opacity(0.72))
                            }
                            Text("\(album.photoCount) \(String(localized: "album.photo-count"))")
                                .font(.caption)
                                .foregroundStyle(AppColors.ink.opacity(0.70))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("album.row.\(album.id.uuidString)")

                    Button {
                        albumToDelete = album
                    } label: {
                        Image(systemName: "trash")
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(AppStrings.albumDelete)
                    .accessibilityIdentifier("album.delete.\(album.id.uuidString)")
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

@MainActor
private struct AlbumCreateScreen: View {
    private let service: any SocialProfileUIService
    private let onCreated: (AlbumSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AlbumCreateScreenModel
    @State private var title = ""
    @State private var description = ""

    init(
        service: any SocialProfileUIService,
        onCreated: @escaping (AlbumSummary) -> Void
    ) {
        self.service = service
        self.onCreated = onCreated
        _model = StateObject(wrappedValue: AlbumCreateScreenModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SocialPrototypeNotice(dataMode: service.dataMode)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField(AppStrings.albumNamePlaceholder, text: $title)
                        .accessibilityIdentifier("album.create.title")
                    TextField(AppStrings.albumDescriptionPlaceholder, text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("album.create.description")
                } header: {
                    Text(AppStrings.albumCreateTitle)
                }

                Section {
                    PrimaryButton(isLoading: model.isWorking) {
                        Task {
                            if let album = await model.create(title: title, description: description) {
                                onCreated(album)
                            }
                        }
                    } label: {
                        Text(AppStrings.albumSave)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("album.create.save")
                }

                SocialActionError(error: model.error)
            }
            .navigationTitle(AppStrings.albumCreateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("posting.flow.close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen.album.create")
    }
}
