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

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isBusy
    }

    func toggleMode() {
        mode = mode.toggled
        errorMessage = nil
    }

    func submit() async {
        guard canSubmit else { return }

        isBusy = true
        errorMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
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
        case .userDisabled:      return "That account has been disabled."
        case .network:           return "Can't reach the network. Check your connection."
        case .tooManyRequests:   return "Too many attempts. Try again in a moment."
        case .notConfigured:     return "Sign-in isn't set up for this app yet."
        case .providerDisabled:  return "Email and password sign-in isn't enabled for this app."
        case .unknown(let description): return description
        }
    }
}
