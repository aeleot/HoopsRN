import Combine
import FirebaseAuth
import Foundation

final class AuthManager: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var hasLoadedInitialState = false
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private var stateListener: AuthStateDidChangeListenerHandle?

    /// Views read session state through these rather than importing FirebaseAuth.
    var isSignedIn: Bool { user != nil }
    var userID: String? { user?.uid }
    var userEmail: String? { user?.email }

    init() {
        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.hasLoadedInitialState = true
            }
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate {
            try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await authenticate {
            try await Auth.auth().createUser(withEmail: email, password: password)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func authenticate(_ action: () async throws -> AuthDataResult) async {
        isBusy = true
        errorMessage = nil
        do {
            _ = try await action()
        } catch {
            errorMessage = Self.message(for: error)
        }
        isBusy = false
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError

        // The SDK has no error case for CONFIGURATION_NOT_FOUND, so it arrives as a
        // generic internal error. It means Authentication was never enabled for the
        // Firebase project — a console setting, not something the user can fix here.
        if String(describing: nsError.userInfo).contains("CONFIGURATION_NOT_FOUND") {
            return "Sign-in isn't set up for this app yet. (Enable Authentication in the Firebase console.)"
        }

        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }

        switch code {
        case .operationNotAllowed:
            return "Email and password sign-in isn't enabled for this app."
        case .invalidEmail:
            return "That email address doesn't look right."
        case .emailAlreadyInUse:
            return "An account already exists for that email."
        case .weakPassword:
            return "Passwords need to be at least 6 characters."
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found for that email."
        case .userDisabled:
            return "That account has been disabled."
        case .networkError:
            return "Can't reach the network. Check your connection."
        case .tooManyRequests:
            return "Too many attempts. Try again in a moment."
        default:
            return error.localizedDescription
        }
    }
}
