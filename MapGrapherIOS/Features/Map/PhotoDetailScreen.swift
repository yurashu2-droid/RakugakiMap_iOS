import Foundation
import SwiftUI
import MapGrapherCore

struct RakugakiSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let authorName: String
    let status: ApprovalStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        authorName: String,
        status: ApprovalStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorName = authorName
        self.status = status
        self.createdAt = createdAt
    }
}

enum PhotoPermissionState: Equatable {
    case loading
    case loaded(PhotoPermissions)
    case forbidden
    case notFound
    case offline
    case error
}

@MainActor
struct PhotoDetailScreen: View {
    let photo: Photo
    let photoReader: any PhotoReading
    let rakugakis: [RakugakiSummary]
    let onOpenAR: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permissionState: PhotoPermissionState = .loading

    init(
        photo: Photo,
        photoReader: any PhotoReading,
        rakugakis: [RakugakiSummary] = [],
        onOpenAR: @escaping () -> Void = {}
    ) {
        self.photo = photo
        self.photoReader = photoReader
        self.rakugakis = rakugakis
        self.onOpenAR = onOpenAR
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    PhotoHeroView(photo: photo)

                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(photo.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColors.ink)
                        Text("map.photo-detail.author")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.ink.opacity(0.70))
                        Text(photo.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(AppColors.ink.opacity(0.62))
                    }

                    permissionSection
                    rakugakiSection
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.vertical, AppSpacing.large)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(Text("map.photo-detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("route.close") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("screen.photo-detail")
        .accessibilityLabel(Text("map.photo-detail.title"))
        .task(id: photo.id) {
            await loadPermissions()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("map.photo-detail.actions")
                .font(.headline)
                .foregroundStyle(AppColors.ink)

            HStack(spacing: AppSpacing.medium) {
                Button {
                    // 描画画面はL03で接続する。権限がない間は操作を許可しない。
                } label: {
                    Label("photo.draw", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDraw)
                .accessibilityIdentifier("photo.draw.button")

                Button {
                    onOpenAR()
                } label: {
                    Label("photo.ar", systemImage: "arkit")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!canView)
                .accessibilityIdentifier("photo.ar.button")
            }

            switch permissionState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel(Text("state.loading"))
                    .accessibilityIdentifier("photo.permissions.loading")
            case .loaded(let permissions) where !permissions.canView:
                Text("map.photo-detail.permission-denied")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.permissions.denied")
            case .loaded:
                EmptyView()
            case .forbidden:
                Text("map.photo-detail.permission-denied")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.permissions.denied")
            case .notFound:
                Text("map.photo-detail.not-found")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            case .offline:
                Text("map.photo-detail.offline")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            case .error:
                Text("state.error.default")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.large)
        .background(AppColors.mint.opacity(0.20), in: RoundedRectangle(cornerRadius: 18))
    }

    private var rakugakiSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("map.rakugaki-list.title")
                .font(.headline)
                .foregroundStyle(AppColors.ink)

            if rakugakis.isEmpty {
                Text("map.rakugaki-list.empty")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("map.rakugaki-list.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(rakugakis) { rakugaki in
                        HStack(spacing: AppSpacing.medium) {
                            Image(systemName: "scribble.variable")
                                .foregroundStyle(AppColors.coral)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                                Text(rakugaki.authorName)
                                    .font(.subheadline.weight(.semibold))
                                Text(rakugaki.status.localizedKey)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.ink.opacity(0.70))
                            }
                            Spacer()
                            Text(rakugaki.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(AppColors.ink.opacity(0.62))
                        }
                        .padding(.vertical, AppSpacing.small)
                    }
                }
                .accessibilityIdentifier("map.rakugaki-list")
            }
        }
    }

    private var canView: Bool {
        if case .loaded(let permissions) = permissionState {
            return permissions.canView
        }
        return false
    }

    private var canDraw: Bool {
        if case .loaded(let permissions) = permissionState {
            return permissions.canDraw
        }
        return false
    }

    private func loadPermissions() async {
        permissionState = .loading
        do {
            let permissions = try await photoReader.permissions(photoID: photo.id)
            guard !Task.isCancelled else { return }
            permissionState = .loaded(permissions)
        } catch let error as PhotoReadingError {
            guard !Task.isCancelled else { return }
            switch error {
            case .permissionDenied, .forbidden:
                permissionState = .forbidden
            case .notFound:
                permissionState = .notFound
            case .offline:
                permissionState = .offline
            case .serviceUnavailable, .unknown:
                permissionState = .error
            }
        } catch {
            guard !Task.isCancelled else { return }
            permissionState = .error
        }
    }
}

@MainActor
private struct PhotoHeroView: View {
    let photo: Photo

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(AppColors.mint.opacity(0.30))
            VStack(spacing: AppSpacing.small) {
                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.coral)
                    .accessibilityHidden(true)
                Text("map.photo-detail.asset-pending")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(photo.title))
        .accessibilityIdentifier("photo.asset")
    }
}

private extension ApprovalStatus {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .pending:
            "map.rakugaki.status.pending"
        case .approved:
            "map.rakugaki.status.approved"
        case .rejected:
            "map.rakugaki.status.rejected"
        }
    }
}
