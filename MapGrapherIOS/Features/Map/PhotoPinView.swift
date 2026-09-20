import SwiftUI
import MapGrapherCore

struct PhotoPinView: View {
    let photo: Photo
    let isSelected: Bool

    init(photo: Photo, isSelected: Bool = false) {
        self.photo = photo
        self.isSelected = isSelected
    }

    var body: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Image(systemName: "pencil.and.outline")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.paper)
                .frame(width: 36, height: 36)
                .background(
                    isSelected ? AppColors.ink : AppColors.coral,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(AppColors.paper, lineWidth: 2)
                }
            Text(photo.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xSmall)
        .background(AppColors.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppColors.ink.opacity(0.12), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(photo.title))
        .accessibilityIdentifier("map.photo-pin.\(photo.id.uuidString)")
    }
}
