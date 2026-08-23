import Combine
import FirebaseAuth
import Foundation

/// The only file in the app that imports FirebaseAuth. Everything above this
/// layer works with `AuthenticatedUser` and `AuthError`, so swapping the
/// provider later touches this file alone.
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: AuthenticatedUser?

    /// Firebase restores a cached session asynchronously, so session state is
    /// genuinely unknown until the first listener callback lands.
    @Published private(set) var hasLoadedInitialState = false

    private var stateListener: AuthStateDidChangeListenerHandle?

    init() {
        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user.map {
                    AuthenticatedUser(id: $0.uid, email: $0.email)
                }
                self?.hasLoadedInitialState = true
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signUp(email: String, password: String) async throws {
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Asks Firebase to email a one-time reset link to `email`.
    ///
    /// This is the app's entire contribution to a password change. Firebase
    /// mints an expiring out-of-band code, emails it, and swaps the stored hash
    /// when the link's page is submitted — the new password is typed *there*,
    /// never here, so nothing about it passes through this process or gets
    /// stored in Firestore. The account's own address is the proof of
    /// ownership, which is why no current password is asked for.
    ///
    /// Completing the reset also revokes the account's refresh tokens, so other
    /// signed-in devices drop back to the login screen.
    func sendPasswordResetEmail(to email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signOut() throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw Self.mapped(error)
        }
    }

    private static func mapped(_ error: Error) -> AuthError {
        let nsError = error as NSError

        // The SDK has no case for CONFIGURATION_NOT_FOUND, so it surfaces as a
        // generic internal error. It means Authentication was never enabled for
        // the Firebase project.
        if String(describing: nsError.userInfo).contains("CONFIGURATION_NOT_FOUND") {
            return .notConfigured
        }

        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return .unknown(error.localizedDescription)
        }

        switch code {
        case .invalidEmail:                   return .invalidEmail
        case .emailAlreadyInUse:              return .emailAlreadyInUse
        case .weakPassword:                   return .weakPassword
        case .wrongPassword, .invalidCredential: return .wrongCredentials
        case .userNotFound:                   return .userNotFound
        case .userDisabled:                   return .userDisabled
        case .networkError:                   return .network
        case .tooManyRequests:                return .tooManyRequests
        case .operationNotAllowed:            return .providerDisabled
        default:                              return .unknown(error.localizedDescription)
        }
    }
}
