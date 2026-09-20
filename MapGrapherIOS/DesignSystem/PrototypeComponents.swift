import SwiftUI

struct PrototypeNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(AppColors.coral)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.prototypeBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.coral)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.mint.opacity(0.24), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct PrototypePlaceholderCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.ink)
            Text(detail)
                .font(.body)
                .foregroundStyle(AppColors.ink.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppColors.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.ink.opacity(0.12), lineWidth: 1)
        }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColors.paper)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 18)
            .background(
                AppColors.coral.opacity(configuration.isPressed ? 0.78 : 1),
                in: Capsule()
            )
    }
}
