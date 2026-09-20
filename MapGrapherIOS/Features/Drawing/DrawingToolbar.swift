import SwiftUI

@MainActor
struct DrawingToolbar: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            Button {
                onContinue()
            } label: {
                Label("posting.drawing.continue", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
            .accessibilityIdentifier("posting.drawing.continue")

            Button("posting.drawing.skip", action: onSkip)
                .frame(minHeight: 44)
                .disabled(!isEnabled)
                .accessibilityIdentifier("posting.drawing.skip")
        }
    }
}
