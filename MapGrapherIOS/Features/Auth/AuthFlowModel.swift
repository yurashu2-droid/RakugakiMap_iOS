import Combine
import Foundation

enum AuthViewState: Equatable {
    case idle
    case submitting
    case confirmationRequired(email: String)
    case passwordResetSent(email: String)
    case failed(AuthUIError)
}

@MainActor
final class AuthFlowModel: ObservableObject {
    @Published private(set) var state: AuthViewState = .idle

    private let service: any AuthUIService

    init(service: any AuthUIService) {
        self.service = service
    }

    var isSubmitting: Bool {
        state == .submitting
    }

    @discardableResult
    func signIn(email: String, password: String) async -> Bool {
        guard state != .submitting else { return false }
        guard isValidEmail(email) else {
            state = .failed(.invalidEmail)
            return false
        }
        guard isValidPassword(password) else {
            state = .failed(.invalidPassword)
            return false
        }

        state = .submitting
        do {
            let outcome = try await service.signIn(email: email, password: password)
            switch outcome {
            case .signedIn:
                state = .idle
                return true
            case .confirmationRequired:
                state = .confirmationRequired(email: email)
                return false
            }
        } catch let error as AuthUIError {
            state = .failed(error)
            return false
        } catch {
            state = .failed(.unknown)
            return false
        }
    }

    @discardableResult
    func signUp(
        email: String,
        displayName: String,
        password: String,
        confirmation: String
    ) async -> Bool {
        guard state != .submitting else { return false }
        guard isValidEmail(email) else {
            state = .failed(.invalidEmail)
            return false
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failed(.invalidDisplayName)
            return false
        }
        guard isValidPassword(password) else {
            state = .failed(.invalidPassword)
            return false
        }
        guard password == confirmation else {
            state = .failed(.passwordMismatch)
            return false
        }

        state = .submitting
        do {
            let outcome = try await service.signUp(
                email: email,
                password: password,
                displayName: displayName
            )
            switch outcome {
            case .signedIn:
                state = .idle
                return true
            case .confirmationRequired:
                state = .confirmationRequired(email: email)
                return false
            }
        } catch let error as AuthUIError {
            state = .failed(error)
            return false
        } catch {
            state = .failed(.unknown)
            return false
        }
    }

    func sendPasswordReset(email: String) async {
        guard state != .submitting else { return }
        guard isValidEmail(email) else {
            state = .failed(.invalidEmail)
            return
        }

        state = .submitting
        do {
            try await service.sendPasswordReset(email: email)
            state = .passwordResetSent(email: email)
        } catch let error as AuthUIError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    func clearFeedback() {
        guard state != .submitting else { return }
        state = .idle
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return !domain.isEmpty && domain.contains(".")
    }

    private func isValidPassword(_ password: String) -> Bool {
        password.count >= 8
    }
}
