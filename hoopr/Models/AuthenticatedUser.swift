import Foundation

/// The app's own representation of a signed-in user, so no Firebase type
/// escapes `AuthService` into the rest of the app.
struct AuthenticatedUser: Equatable, Sendable {
    let id: String
    let email: String?
}

/// Domain-level auth failures. `AuthService` translates Firebase's errors into
/// these; view models decide how to word them for people.
enum AuthError: Error, Equatable {
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case wrongCredentials
    case userNotFound
    case userDisabled
    case network
    case tooManyRequests
    /// Authentication isn't provisioned for the Firebase project at all.
    case notConfigured
    /// The project exists but email/password sign-in is switched off.
    case providerDisabled
    /// The keychain refused to store or read the session. Sign-in itself
    /// succeeded — Firebase only touches the keychain once the server has
    /// accepted the credentials, which is why this never appears for a wrong
    /// password. Almost always a build that carries no `application-identifier`
    /// entitlement, so `securityd` denies every access group (`-34018`).
    case keychainUnavailable
    case unknown(String)
}
