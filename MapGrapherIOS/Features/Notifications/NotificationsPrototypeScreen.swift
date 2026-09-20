import SwiftUI

struct NotificationsPrototypeScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrototypeNotice(message: AppStrings.backendNotice)
                    PrototypePlaceholderCard(
                        title: AppStrings.notificationsPreviewTitle,
                        detail: AppStrings.notificationsPreviewDetail
                    )
                }
                .padding(20)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.notifications)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.notifications")
        .accessibilityLabel(Text(AppStrings.notifications))
    }
}
