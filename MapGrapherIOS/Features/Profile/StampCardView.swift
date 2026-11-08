import SwiftUI

/// 案Aのスタンプカード。黄色の面を少し傾け（約−1.5度）、集めた数と両端の丸い太い棒で進み具合を見せる
@MainActor
struct StampCardView: View {
    let stats: StampCardStats?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.shuEdge)
                    .accessibilityHidden(true)
                Text(AppStrings.profileStats)
                    .font(.headline.weight(.bold))
            }

            if let stats {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text("\(stats.earned)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                    Text("/ \(stats.total)")
                        .font(.title3.weight(.bold))
                        .opacity(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("profile.stats.progress \(stats.earned) \(stats.total)"))

                progressBar(stats)
            } else {
                Text(AppStrings.profileStatsEmpty)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.stats.empty")
            }
        }
        .foregroundStyle(AppColors.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.yellow)
                .shadow(color: AppColors.yellowEdge.opacity(0.35), radius: 10, y: 6)
        }
        .rotationEffect(.degrees(-1.5))
        .padding(.horizontal, AppSpacing.xSmall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.stats")
    }

    private func progressBar(_ stats: StampCardStats) -> some View {
        let ratio = stats.total > 0 ? CGFloat(stats.earned) / CGFloat(stats.total) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white)
                Capsule()
                    .fill(AppColors.shu)
                    .frame(width: max(proxy.size.width * ratio, ratio > 0 ? 12 : 0))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
