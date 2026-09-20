import Foundation
import Observation
import MapGrapherCore

@MainActor
protocol ProfileBootstrapServing {
    func profileExists(context: SessionContext) async throws -> Bool
    func createProfile(context: SessionContext, displayName: String, uniqueID: String) async throws
}

enum ProfileBootstrapState: Equatable {
    case loading
    case needsProfile
    case saving
    case ready
    case failed(String)
}

@MainActor @Observable
final class ProfileBootstrapModel {
    private(set) var state: ProfileBootstrapState = .loading
    private let context: SessionContext
    private let session: SessionController
    private let service: any ProfileBootstrapServing

    init(context: SessionContext, session: SessionController, service: any ProfileBootstrapServing) {
        self.context = context
        self.session = session
        self.service = service
    }

    var canOpenApp: Bool { state == .ready }

    func load() async {
        guard await session.isCurrent(context) else { return }
        state = .loading
        do {
            let exists = try await service.profileExists(context: context)
            guard await session.isCurrent(context) else { return }
            state = exists ? .ready : .needsProfile
        } catch {
            guard await session.isCurrent(context) else { return }
            state = .failed("プロフィールを確認できませんでした。通信を確認して再試行してください。")
        }
    }

    func submit(displayName: String, uniqueID: String) async {
        guard state == .needsProfile || isFailed else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64 else {
            state = .failed("表示名は1〜64文字で入力してください。")
            return
        }
        guard identifier.range(of: "^[A-Za-z0-9_.]{3,32}$", options: .regularExpression) != nil else {
            state = .failed("公開IDは英数字・_・.を使い、3〜32文字で入力してください。")
            return
        }
        guard await session.isCurrent(context) else { return }
        state = .saving
        do {
            try await service.createProfile(context: context, displayName: name, uniqueID: identifier)
            guard await session.isCurrent(context) else { return }
            state = .ready
        } catch {
            guard await session.isCurrent(context) else { return }
            state = .failed("プロフィールを保存できませんでした。公開IDの重複や通信状態を確認してください。")
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
