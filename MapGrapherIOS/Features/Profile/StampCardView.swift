import SwiftUI

@MainActor
struct StampCardView: View {
    let stats: StampCardStats?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(AppStrings.profileStats)
                .font(.headline)

            if let stats {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text("\(stats.earned)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/ \(stats.total)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.ink.opacity(0.70))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(stats.earned) / \(stats.total)"))
            } else {
                Text(AppStrings.profileStatsEmpty)
                    .font(.body)
                    .foregroundStyle(AppColors.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.stats.empty")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.mint.opacity(0.20), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("profile.stats")
    }
}
