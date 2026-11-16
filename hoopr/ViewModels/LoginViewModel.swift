import Combine
import Foundation

/// Owns the whole login form: field contents, which mode we're in, in-flight
/// state, and how a domain `AuthError` gets worded for the person reading it.
final class LoginViewModel: ObservableObject {
    enum Mode {
        case signIn
        case signUp

        var title: String {
            switch self {
            case .signIn: "Welcome back"
            case .signUp: "Create your account"
            }
        }

        var actionLabel: String {
            switch self {
            case .signIn: "Sign In"
            case .signUp: "Sign Up"
            }
        }

        var switchPrompt: String {
            switch self {
            case .signIn: "Don't have an account?"
            case .signUp: "Already have an account?"
            }
        }

        var switchAction: String {
            switch self {
            case .signIn: "Sign up"
            case .signUp: "Sign in"
            }
        }

        var toggled: Mode {
            switch self {
            case .signIn: .signUp
            case .signUp: .signIn
            }
        }
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    /// Something to tell the reader that isn't a failure — today, only that a
    /// reset link went out. Separate from `errorMessage` so the view can draw
    /// it without the red.
    @Published private(set) var noticeMessage: String?

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !Self.normalizedEmail(email).isEmpty
            && !password.isEmpty
            && !isBusy
    }

    /// "Forgot password?" belongs to signing in: someone creating an account
    /// has no password to have forgotten.
    var offersPasswordReset: Bool { mode == .signIn }

    func toggleMode() {
        mode = mode.toggled
        errorMessage = nil
        noticeMessage = nil
    }

    /// The address as it is sent. `.whitespacesAndNewlines`, not
    /// `.whitespaces`: an email pasted from a message often carries a trailing
    /// newline, which Firebase rejects as an invalid address.
    nonisolated static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the reset link's confirmation says. **The same sentence whether or
    /// not the account exists**, so this screen can't be used to find out
    /// which addresses have accounts.
    nonisolated static let passwordResetNotice =
        "If an account exists for that email, we've sent a link to reset your password."

    nonisolated static let passwordResetNeedsEmail =
        "Enter your email above, then tap Forgot password."

    /// Emails a reset link to the address in the email field — the only way
    /// back in for someone who is signed out and has forgotten their password.
    /// (Profile has its own, for a signed-in account changing one.)
    func sendPasswordReset() async {
        guard !isBusy else { return }

        let trimmedEmail = Self.normalizedEmail(email)
        guard !trimmedEmail.isEmpty else {
            noticeMessage = nil
            errorMessage = Self.passwordResetNeedsEmail
            return
        }

        isBusy = true
        errorMessage = nil
        noticeMessage = nil

        do {
            try await authService.sendPasswordResetEmail(to: trimmedEmail)
            noticeMessage = Self.passwordResetNotice
        } catch {
            let outcome = Self.passwordResetOutcome(for: error)
            noticeMessage = outcome.notice
            errorMessage = outcome.error
        }

        isBusy = false
    }

    /// How a failed reset request is reported. `userNotFound` is reported as
    /// the *success* notice: projects without email-enumeration protection
    /// return it, and repeating it would confirm who has no account.
    nonisolated static func passwordResetOutcome(for error: Error) -> (notice: String?, error: String?) {
        guard let authError = error as? AuthError else {
            return (nil, "Couldn't send the reset link. Try again.")
        }

        switch authError {
        case .userNotFound:     return (passwordResetNotice, nil)
        case .invalidEmail:     return (nil, "That email address doesn't look right.")
        case .userDisabled:     return (nil, FailureText.accountDisabled)
        case .network:          return (nil, FailureText.network)
        case .tooManyRequests:  return (nil, "Too many attempts. Try again in a few minutes.")
        case .notConfigured:    return (nil, FailureText.authNotConfigured)
        case .providerDisabled: return (nil, FailureText.providerDisabled)
        default:                return (nil, "Couldn't send the reset link. Try again.")
        }
    }

    func submit() async {
        guard canSubmit else { return }

        isBusy = true
        errorMessage = nil
        noticeMessage = nil

        let trimmedEmail = Self.normalizedEmail(email)
        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: trimmedEmail, password: password)
            case .signUp:
                try await authService.signUp(email: trimmedEmail, password: password)
            }
        } catch {
            errorMessage = Self.message(for: error)
        }

        isBusy = false
    }

    private static func message(for error: Error) -> String {
        guard let authError = error as? AuthError else {
            return error.localizedDescription
        }

        switch authError {
        case .invalidEmail:      return "That email address doesn't look right."
        case .emailAlreadyInUse: return "An account already exists for that email."
        case .weakPassword:      return "Passwords need to be at least 6 characters."
        case .wrongCredentials:  return "Incorrect email or password."
        case .userNotFound:      return "No account found for that email."
        case .userDisabled:      return FailureText.accountDisabled
        case .network:           return FailureText.network
        case .tooManyRequests:   return "Too many attempts. Try again in a moment."
        case .notConfigured:     return FailureText.authNotConfigured
        case .providerDisabled:  return FailureText.providerDisabled
        case .keychainUnavailable:
            return "Signed in, but this device wouldn't store the session. Reinstall the app and try again."
        case .requiresRecentLogin:
            return "Sign in again to continue."
        case .unknown(let description): return description
        }
    }
}
