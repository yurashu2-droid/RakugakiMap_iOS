import SwiftUI
import MapGrapherCore

@MainActor
struct PhotoListScreen: View {
    let photos: [Photo]
    let filter: PhotoFilter
    let onSelect: (Photo) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    LoadStateView(
                        state: .empty,
                        emptyMessage: "map.photo-list.empty"
                    ) {
                        EmptyView()
                    }
                } else {
                    List(photos, id: \.id) { photo in
                        Button {
                            onSelect(photo)
                        } label: {
                            PhotoListRow(photo: photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("map.photo-row.\(photo.id.uuidString)")
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("map.photo-list")
                }
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(Text("map.photo-list.title"))
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
        .accessibilityIdentifier("screen.photo-list")
        .accessibilityLabel(Text("map.photo-list.title"))
        .accessibilityHint(Text(filter.titleKey))
    }
}

@MainActor
private struct PhotoListRow: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            PhotoPinView(photo: photo)
                .frame(width: 72)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(photo.title)
                    .font(.headline)
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(2)
                Text("map.photo-list.author")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink.opacity(0.70))
                Text(photo.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(AppColors.ink.opacity(0.62))
            }

            Spacer(minLength: AppSpacing.small)
            Image(systemName: "chevron.forward")
                .foregroundStyle(AppColors.ink.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.small)
        .contentShape(Rectangle())
    }
}

private extension PhotoFilter {
    var titleKey: LocalizedStringKey {
        switch self {
        case .all:
            "map.filter.all"
        case .friends:
            "map.filter.friends"
        case .recent24Hours:
            "map.filter.recent"
        }
    }
}
