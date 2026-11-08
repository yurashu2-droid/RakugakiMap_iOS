import SwiftUI

/// 案Aの下のタブ。画面の端から浮かせた角丸の板にのせ、選んでいるタブだけ、その画面の色のインクのしぶきで示す。
/// 標準のタブバーではしぶきを置けないため自前で描く。XCUITestは`tab.<名前>`の識別子と選択状態で取得する。
struct RakugakiTabBar: View {
    @Binding var selection: AppRoute.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppRoute.Tab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, AppSpacing.xSmall)
        .frame(height: 64)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppRoute.Tab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 72, height: 30)
                    .background {
                        if selected {
                            // 選んだ瞬間にしぶきが広がる
                            InkSplatView(seed: tab.splatSeed, color: tab.splatColor, splashKey: tab)
                                .frame(width: 72, height: 42)
                        }
                    }
                Text(tab.title)
                    .font(.caption2.weight(selected ? .heavy : .semibold))
            }
            .foregroundStyle(selected ? AppColors.onAccent : AppColors.muted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension AppRoute.Tab {
    @MainActor
    var title: LocalizedStringKey {
        switch self {
        case .today: AppStrings.today
        case .groups: AppStrings.groups
        case .map: AppStrings.map
        case .notifications: AppStrings.notifications
        case .profile: AppStrings.profile
        }
    }

    var symbol: String {
        switch self {
        case .today: "house.fill"
        case .groups: "person.2.fill"
        case .map: "mappin.and.ellipse"
        case .notifications: "bell.fill"
        case .profile: "person.crop.circle.fill"
        }
    }

    /// 開いている画面ごとに、しぶきの色を変える（Androidと同じ割り当て）
    var splatColor: Color {
        switch self {
        case .today: AppColors.yellow
        case .groups: AppColors.fuji
        case .map: AppColors.shu
        case .notifications: AppColors.sky
        case .profile: AppColors.lime
        }
    }

    var splatSeed: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) * 7919 + 101
    }
}
