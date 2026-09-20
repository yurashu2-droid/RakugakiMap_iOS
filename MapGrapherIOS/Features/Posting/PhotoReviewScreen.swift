import SwiftUI
import UIKit

@MainActor
struct PhotoReviewScreen: View {
    let image: PreparedPostingImage
    let onRetake: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Text("posting.review.title")
                        .font(.title.bold())
                        .foregroundStyle(AppColors.ink)
                    Text("posting.review.detail")
                        .font(.body)
                        .foregroundStyle(AppColors.ink.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                preview

                VStack(spacing: AppSpacing.medium) {
                    Button {
                        onContinue()
                    } label: {
                        Label("posting.review.continue", systemImage: "pencil.and.outline")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("posting.review.continue")

                    Button("posting.review.retake", action: onRetake)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("posting.review.retake")
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.large)
        }
        .background(AppColors.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.posting.review")
        .accessibilityLabel(Text("posting.review.title"))
    }

    @ViewBuilder
    private var preview: some View {
        if let uiImage = UIImage(data: image.previewData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)
                .background(AppColors.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel(Text("posting.review.preview"))
                .accessibilityIdentifier("posting.review.preview")
        } else {
            ContentUnavailableView(
                "posting.review.unavailable.title",
                systemImage: "photo.badge.exclamationmark",
                description: Text("posting.review.unavailable.detail")
            )
            .frame(minHeight: 220)
            .accessibilityIdentifier("posting.review.preview")
        }
    }
}
