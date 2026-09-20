import SwiftUI

struct PrimaryButton<Label: View>: View {
    let isLoading: Bool
    let action: () -> Void
    private let label: Label

    init(
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isLoading = isLoading
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(AppColors.paper)
                        .accessibilityLabel(Text("state.loading"))
                } else {
                    label
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(AppPrimaryButtonStyle())
        .disabled(isLoading)
        .accessibilityAddTraits(isLoading ? .isStaticText : [])
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColors.paper)
            .padding(.horizontal, AppSpacing.large)
            .background(
                AppColors.coral.opacity(
                    isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45
                ),
                in: Capsule()
            )
            .frame(minHeight: 48)
            .contentShape(Capsule())
    }
}
