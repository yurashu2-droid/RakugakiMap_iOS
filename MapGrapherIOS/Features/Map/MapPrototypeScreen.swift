import SwiftUI

struct MapPrototypeScreen: View {
    let isUITesting: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrototypeNotice(message: AppStrings.backendNotice)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.mapPreviewTitle)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppColors.ink)
                        Text(AppStrings.mapPreviewDetail)
                            .font(.body)
                            .foregroundStyle(AppColors.ink.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NavigationLink {
                        ARProbeScreen(isUITesting: isUITesting)
                    } label: {
                        Label(AppStrings.arPreviewButton, systemImage: "arkit")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("map.ar-preview.button")
                    .accessibilityLabel(Text(AppStrings.arPreviewButton))

                    PrototypePlaceholderCard(
                        title: AppStrings.mapPlaceholderTitle,
                        detail: AppStrings.mapPlaceholderDetail
                    )
                }
                .padding(20)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.map)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.map")
        .accessibilityLabel(Text(AppStrings.map))
    }
}
