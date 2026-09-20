import SwiftUI

@MainActor
struct ProfileEditScreen: View {
    private let service: any SocialProfileUIService
    @StateObject private var model: ProfileEditScreenModel
    @State private var displayName = ""

    init(service: any SocialProfileUIService = FakeSocialProfileUIService()) {
        self.service = service
        _model = StateObject(wrappedValue: ProfileEditScreenModel(service: service))
    }

    var body: some View {
        Form {
            Section {
                SocialPrototypeNotice(dataMode: service.dataMode)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField(AppStrings.profileDisplayNamePlaceholder, text: $displayName)
                    .textContentType(.name)
                    .accessibilityIdentifier("profile.edit.display-name")
            } header: {
                Text(AppStrings.profileDisplayName)
            } footer: {
                Text(AppStrings.profileEditDetail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                PrimaryButton(isLoading: model.isSaving) {
                    Task { await model.save(displayName: displayName) }
                } label: {
                    Text("profile.save")
                        .frame(maxWidth: .infinity)
                }
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("profile.edit.save")
            }

            if model.didSave {
                SocialActionNotice(dataMode: service.dataMode)
            }

            if model.error != nil {
                SocialActionError(error: model.error)
            }
        }
        .navigationTitle(AppStrings.profileEdit)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if let profile = model.profile {
                displayName = profile.displayName
            }
        }
        .overlay {
            if model.state == .loading {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityIdentifier("state.loading")
            }
        }
        .accessibilityIdentifier("screen.profile.edit")
    }
}
