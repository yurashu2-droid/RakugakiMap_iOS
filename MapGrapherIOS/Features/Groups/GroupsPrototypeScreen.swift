import SwiftUI

struct GroupsPrototypeScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrototypeNotice(message: AppStrings.backendNotice)
                    PrototypePlaceholderCard(
                        title: AppStrings.groupsPreviewTitle,
                        detail: AppStrings.groupsPreviewDetail
                    )
                }
                .padding(20)
            }
            .background(AppColors.paper.ignoresSafeArea())
            .navigationTitle(AppStrings.groups)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.groups")
        .accessibilityLabel(Text(AppStrings.groups))
    }
}
