import CoreGraphics
import Foundation
import ImageIO
import MapGrapherCore
import SwiftUI

@MainActor
struct DrawingScreen: View {
    let preparedImage: PreparedPostingImage
    let document: DrawingDocument?
    let onDocumentChange: (DrawingDocument) -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    private let baseImage: CGImage?

    init(
        preparedImage: PreparedPostingImage,
        document: DrawingDocument?,
        onDocumentChange: @escaping (DrawingDocument) -> Void,
        onSkip: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.preparedImage = preparedImage
        self.document = document
        self.onDocumentChange = onDocumentChange
        self.onSkip = onSkip
        self.onContinue = onContinue
        baseImage = CGImageSourceCreateWithData(preparedImage.previewData as CFData, nil)
            .flatMap { source in
                CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            if let baseImage,
               let initialDocument = document ?? makeDocument(for: baseImage) {
                DrawingCanvasView(
                    baseImage: baseImage,
                    document: initialDocument,
                    onDocumentChange: onDocumentChange
                )
                .accessibilityIdentifier("posting.drawing.canvas")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                DrawingToolbar(
                    onSkip: onSkip,
                    onContinue: onContinue,
                    isEnabled: true
                )
                .padding(.horizontal, AppSpacing.medium)
            } else {
                ContentUnavailableView(
                    "posting.drawing.unavailable.title",
                    systemImage: "scribble.variable",
                    description: Text("posting.drawing.unavailable.detail")
                )
                .frame(maxHeight: .infinity)
                Button("posting.drawing.skip", action: onSkip)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("posting.drawing.skip")
            }
        }
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.posting.drawing")
        .accessibilityLabel(Text("posting.drawing.title"))
    }

    private func makeDocument(for image: CGImage) -> DrawingDocument? {
        DrawingDocument(pixelWidth: image.width, pixelHeight: image.height, strokes: [])
    }
}
