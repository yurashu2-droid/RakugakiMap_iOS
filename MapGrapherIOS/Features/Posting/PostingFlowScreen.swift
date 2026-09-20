import SwiftUI

@MainActor
struct PostingFlowScreen: View {
    let isUITesting: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PostingFlowModel
    @State private var showsCloseDialog = false

    init(
        isUITesting: Bool = false,
        service: any PostingUIService = FakePostingUIService(),
        missionID: UUID? = nil
    ) {
        self.isUITesting = isUITesting
        _model = StateObject(
            wrappedValue: PostingFlowModel(service: service, missionID: missionID)
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(titleKey)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.canGoBack {
                            Button("posting.flow.back", systemImage: "chevron.backward") {
                                model.goBack()
                            }
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("posting.flow.back")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("posting.flow.close") {
                            showsCloseDialog = true
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("posting.close.button")
                    }
                }
        }
        .background(AppColors.paper)
        .interactiveDismissDisabled(model.hasUnsavedDraft)
        .confirmationDialog(
            "posting.close.title",
            isPresented: $showsCloseDialog,
            titleVisibility: .visible
        ) {
            if model.hasUnsavedDraft && model.storesDraftsPersistently {
                Button("posting.close.save") {
                    Task {
                        if await model.saveAndClose() {
                            dismiss()
                        }
                    }
                }
                .accessibilityIdentifier("posting.close.save")
            }

            if model.hasUnsavedDraft {
                Button("posting.close.discard", role: .destructive) {
                    model.discardDraft()
                    dismiss()
                }
                .accessibilityIdentifier("posting.close.discard")
            } else {
                Button("posting.close.close") {
                    dismiss()
                }
                .accessibilityIdentifier("posting.close.close")
            }
            Button("posting.close.cancel", role: .cancel) {}
        } message: {
            Text(
                model.hasUnsavedDraft
                    ? (model.storesDraftsPersistently
                       ? LocalizedStringKey("posting.close.detail")
                       : LocalizedStringKey("posting.close.prototype-detail"))
                    : LocalizedStringKey("posting.close.empty-detail")
            )
        }
        .task {
            await model.loadLocation()
        }
        .accessibilityIdentifier("screen.posting.flow")
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .capture:
            CaptureScreen(
                isUITesting: isUITesting,
                isBusy: model.isBusy,
                error: model.error,
                onImport: { data, filename in
                    await model.importImage(data: data, suggestedFilename: filename)
                },
                onUseFixture: {
                    await model.useUITestFixture()
                }
            )
        case .review:
            if let preparedImage = model.draft.preparedImage {
                PhotoReviewScreen(
                    image: preparedImage,
                    onRetake: model.goBack,
                    onContinue: model.advanceFromReview
                )
            } else {
                invalidDraftView
            }
        case .drawing:
            if let preparedImage = model.draft.preparedImage {
                DrawingScreen(
                    preparedImage: preparedImage,
                    document: model.draft.drawing,
                    onDocumentChange: model.updateDrawing,
                    onSkip: model.skipDrawing,
                    onContinue: model.advanceFromDrawing
                )
            } else {
                invalidDraftView
            }
        case .publish:
            PublishScreen(
                draft: model.draft,
                isBusy: model.isBusy,
                error: model.error,
                showsNewOperationNotice: model.isEditingSubmittedDraft,
                onTitleChange: model.setTitle,
                onVisibilityChange: model.setVisibility,
                onDrawPermissionChange: model.setDrawPermission,
                onApprovalChange: model.setRequiresApproval,
                onReserveARChange: model.setReserveAR,
                onSubmit: {
                    Task { await model.publish() }
                }
            )
        case .status:
            SubmissionStatusScreen(
                result: model.status,
                error: model.error,
                isBusy: model.isBusy,
                isPrototype: !model.performsNetworkSubmission,
                waitingForApproval: model.draft.reserveAR && model.draft.requiresApproval,
                onRetry: {
                    Task { await model.retrySubmission() }
                },
                onBack: model.goBack
            )
        }
    }

    private var titleKey: LocalizedStringKey {
        switch model.step {
        case .capture:
            "posting.capture.title"
        case .review:
            "posting.review.title"
        case .drawing:
            "posting.drawing.title"
        case .publish:
            "posting.publish.title"
        case .status:
            "posting.status.title"
        }
    }

    private var invalidDraftView: some View {
        ContentUnavailableView(
            "posting.error.invalid-draft",
            systemImage: "doc.badge.gearshape",
            description: Text("posting.error.invalid-draft.detail")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.paper.ignoresSafeArea())
    }
}
