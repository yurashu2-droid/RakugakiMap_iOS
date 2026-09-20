import SwiftUI

enum LoadState: Equatable {
    case idle
    case loading
    case content
    case empty
    case error
}

struct LoadStateView<Content: View>: View {
    let state: LoadState
    let emptyMessage: LocalizedStringKey
    let errorMessage: LocalizedStringKey
    let retry: (() -> Void)?
    private let content: Content

    init(
        state: LoadState,
        emptyMessage: LocalizedStringKey = "state.empty.default",
        errorMessage: LocalizedStringKey = "state.error.default",
        retry: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.emptyMessage = emptyMessage
        self.errorMessage = errorMessage
        self.retry = retry
        self.content = content()
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                Color.clear
                    .frame(minHeight: 1)
                    .accessibilityHidden(true)
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("state.loading"))
                    .accessibilityIdentifier("state.loading")
            case .content:
                content
            case .empty:
                ContentUnavailableView(
                    Text("state.empty.title"),
                    systemImage: "tray",
                    description: Text(emptyMessage)
                )
                .accessibilityIdentifier("state.empty")
            case .error:
                VStack(spacing: AppSpacing.medium) {
                    ContentUnavailableView(
                        Text("state.error.title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    if let retry {
                        Button("state.retry", action: retry)
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                    }
                }
                .accessibilityIdentifier("state.error")
            }
        }
    }
}
