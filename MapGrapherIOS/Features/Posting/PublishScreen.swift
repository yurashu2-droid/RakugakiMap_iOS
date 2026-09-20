import Foundation
import MapGrapherCore
import SwiftUI

@MainActor
struct PublishScreen: View {
    let draft: PostingDraft
    let isBusy: Bool
    let error: PostingFlowError?
    let showsNewOperationNotice: Bool
    let onTitleChange: (String) -> Void
    let onVisibilityChange: (Visibility) -> Void
    let onDrawPermissionChange: (Visibility) -> Void
    let onApprovalChange: (Bool) -> Void
    let onReserveARChange: (Bool) -> Void
    let onSubmit: () -> Void

    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            if showsNewOperationNotice {
                Section {
                    Label("posting.publish.new-operation", systemImage: "arrow.triangle.branch")
                        .foregroundStyle(AppColors.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("posting.publish.new-operation")
                }
            }

            Section {
                TextField(
                    "posting.publish.title.placeholder",
                    text: Binding(
                        get: { draft.title },
                        set: onTitleChange
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)
                .focused($titleFocused)
                .accessibilityIdentifier("posting.publish.title")
            } header: {
                Text("posting.publish.title.label")
            } footer: {
                Text("posting.publish.title.detail")
            }

            Section {
                LabeledContent("posting.publish.location") {
                    if let location = draft.location {
                        Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppColors.ink.opacity(0.78))
                            .accessibilityLabel(Text("posting.publish.location.available"))
                    } else {
                        Text("posting.publish.location.missing")
                            .foregroundStyle(AppColors.coral)
                    }
                }
                Text("posting.publish.location.detail")
                    .font(.caption)
                    .foregroundStyle(AppColors.ink.opacity(0.68))
            }

            Section {
                Picker("posting.publish.visibility", selection: Binding(
                    get: { draft.visibility.rawValue },
                    set: { rawValue in
                        if let value = Visibility(rawValue: rawValue) {
                            onVisibilityChange(value)
                        }
                    }
                )) {
                    ForEach(Visibility.postingChoices, id: \.rawValue) { value in
                        Text(value.postingLabelKey).tag(value.rawValue)
                    }
                }
                .accessibilityIdentifier("posting.publish.visibility")

                Picker("posting.publish.draw-permission", selection: Binding(
                    get: { draft.drawPermission.rawValue },
                    set: { rawValue in
                        if let value = Visibility(rawValue: rawValue) {
                            onDrawPermissionChange(value)
                        }
                    }
                )) {
                    ForEach(Visibility.postingChoices, id: \.rawValue) { value in
                        Text(value.postingDrawLabelKey).tag(value.rawValue)
                    }
                }
                .accessibilityIdentifier("posting.publish.draw-permission")

                Toggle(
                    "posting.publish.approval",
                    isOn: Binding(
                        get: { draft.requiresApproval },
                        set: onApprovalChange
                    )
                )
                .accessibilityIdentifier("posting.publish.approval")
            } header: {
                Text("posting.publish.access.header")
            } footer: {
                Text("posting.publish.access.detail")
            }

            Section {
                Toggle(
                    "posting.publish.ar",
                    isOn: Binding(
                        get: { draft.reserveAR },
                        set: onReserveARChange
                    )
                )
                .disabled(!draft.hasDrawing)
                .accessibilityIdentifier("posting.publish.ar")

                if draft.hasDrawing {
                    Text("posting.publish.ar.detail")
                        .font(.caption)
                        .foregroundStyle(AppColors.ink.opacity(0.68))
                } else {
                    Text("posting.publish.ar.disabled")
                        .font(.caption)
                        .foregroundStyle(AppColors.ink.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("posting.publish.ar.disabled")
                }
            } header: {
                Text("posting.publish.ar.header")
            }

            if let error {
                Section {
                    PostingErrorView(error: error)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Button {
                    onSubmit()
                } label: {
                    if isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        Label("posting.publish.submit", systemImage: "tray.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || draft.location == nil)
                .accessibilityIdentifier("posting.publish.submit")
            } footer: {
                Text("posting.publish.submit.detail")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.posting.publish")
        .accessibilityLabel(Text("posting.publish.title"))
    }
}

private extension Visibility {
    static var postingChoices: [Visibility] { [.onlyMe, .friends, .anyone] }

    var postingLabelKey: LocalizedStringKey {
        switch self {
        case .onlyMe:
            "posting.visibility.only-me"
        case .friends:
            "posting.visibility.friends"
        case .anyone:
            "posting.visibility.anyone"
        }
    }

    var postingDrawLabelKey: LocalizedStringKey {
        switch self {
        case .onlyMe:
            "posting.draw-permission.only-me"
        case .friends:
            "posting.draw-permission.friends"
        case .anyone:
            "posting.draw-permission.anyone"
        }
    }
}
