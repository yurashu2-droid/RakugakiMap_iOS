import SwiftUI

struct ProfilePrototypeScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrototypeNotice(message: AppStrings.backendNotice)
                    PrototypePlaceholderCard(
                        title: AppStrings.profilePreviewTitle,
                        detail: AppStrings.profilePreviewDetail
                    )
                }
                .padding(20)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.profile)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profile")
        .accessibilityLabel(Text(AppStrings.profile))
    }
}
