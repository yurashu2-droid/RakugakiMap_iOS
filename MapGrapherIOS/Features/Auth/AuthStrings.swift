import SwiftUI

@MainActor
enum AuthStrings {
    static let welcomeTitle = LocalizedStringKey("auth.welcome.title")
    static let welcomeDetail = LocalizedStringKey("auth.welcome.detail")
    static let signIn = LocalizedStringKey("auth.sign-in")
    static let signUp = LocalizedStringKey("auth.sign-up")
    static let passwordReset = LocalizedStringKey("auth.password-reset")

    static let signInTitle = LocalizedStringKey("auth.sign-in.title")
    static let signUpTitle = LocalizedStringKey("auth.sign-up.title")
    static let passwordResetTitle = LocalizedStringKey("auth.password-reset.title")
    static let email = LocalizedStringKey("auth.email")
    static let displayName = LocalizedStringKey("auth.display-name")
    static let password = LocalizedStringKey("auth.password")
    static let passwordConfirmation = LocalizedStringKey("auth.password-confirmation")
    static let submit = LocalizedStringKey("auth.submit")
    static let retry = LocalizedStringKey("auth.retry")
    static let confirmationTitle = LocalizedStringKey("auth.confirmation.title")
    static let confirmationDetail = LocalizedStringKey("auth.confirmation.detail")
    static let resetSentTitle = LocalizedStringKey("auth.reset-sent.title")
    static let resetSentDetail = LocalizedStringKey("auth.reset-sent.detail")
    static let backToSignIn = LocalizedStringKey("auth.back-to-sign-in")

    static let invalidEmail = LocalizedStringKey("auth.error.invalid-email")
    static let invalidDisplayName = LocalizedStringKey("auth.error.invalid-display-name")
    static let invalidPassword = LocalizedStringKey("auth.error.invalid-password")
    static let passwordMismatch = LocalizedStringKey("auth.error.password-mismatch")
    static let invalidCredentials = LocalizedStringKey("auth.error.invalid-credentials")
    static let emailAlreadyRegistered = LocalizedStringKey("auth.error.email-already-registered")
    static let emailNotConfirmed = LocalizedStringKey("auth.error.email-not-confirmed")
    static let serviceUnavailable = LocalizedStringKey("auth.error.service-unavailable")
    static let unknown = LocalizedStringKey("auth.error.unknown")
}

@MainActor
extension AuthUIError {
    var localizedMessage: LocalizedStringKey {
        switch self {
        case .invalidEmail:
            AuthStrings.invalidEmail
        case .invalidDisplayName:
            AuthStrings.invalidDisplayName
        case .invalidPassword:
            AuthStrings.invalidPassword
        case .passwordMismatch:
            AuthStrings.passwordMismatch
        case .invalidCredentials:
            AuthStrings.invalidCredentials
        case .emailAlreadyRegistered:
            AuthStrings.emailAlreadyRegistered
        case .emailNotConfirmed:
            AuthStrings.emailNotConfirmed
        case .serviceUnavailable:
            AuthStrings.serviceUnavailable
        case .unknown:
            AuthStrings.unknown
        }
    }
}
