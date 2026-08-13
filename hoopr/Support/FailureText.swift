import Foundation

/// Sentences that more than one error mapper needs to produce.
///
/// The app words its failures in four places — `LoginViewModel`,
/// `ProfileViewModel`, `GameService` and `UserProfileService` — and several
/// sentences were byte-identical across them. Identical copies drift: the
/// wording gets improved in one mapper and not the others, and the app ends up
/// describing one condition two different ways depending on which screen you
/// hit it from.
///
/// Only genuinely shared sentences belong here. Anything a single flow words
/// for itself stays at its call site, where the reason for the wording is
/// visible — `ProfileViewModel` deliberately says something different from
/// `LoginViewModel` about an invalid email, because one is asking you to fix a
/// typo and the other is reporting that your saved address is unusable.
///
/// `nonisolated` because the project defaults to `MainActor` isolation, and the
/// error mappers that read these are themselves `nonisolated static` — they're
/// pure functions the tests call directly, off the main actor. Immutable
/// `String` constants have nothing to isolate.
nonisolated enum FailureText {
    static let network = "Can't reach the network. Check your connection."

    static let signedOut = "You're signed out."

    static let accountDisabled = "That account has been disabled."

    static let authNotConfigured = "Sign-in isn't set up for this app yet."

    static let providerDisabled = "Email and password sign-in isn't enabled for this app."

    /// A **read** was refused by the security rules.
    ///
    /// Both services' read queries are shaped to match a rule that grants any
    /// signed-in user, so a refusal there means the rules the server is running
    /// aren't the rules in this repo — a deployment problem rather than
    /// anything the user did. See `GameService.message(for:whileDoing:context:)`
    /// for why a refused *write* reads differently.
    static func rulesNotDeployed(loading subject: String) -> String {
        "Can't load \(subject) — the server refused the request. The Firestore security rules are probably not deployed."
    }
}
