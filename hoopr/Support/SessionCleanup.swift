import Foundation

/// What is left on the device by one account and must not be handed to the
/// next: scheduled reminders, recent courts, dismissed inbox cards, and which
/// wins have already been celebrated.
///
/// **Keyed on the account changing, not on the Sign Out button.** A session
/// also ends when a password reset revokes its tokens or the account is
/// deleted, and neither passes through `ProfileViewModel.signOut()`. So
/// `hooprApp` watches `AuthService.currentUser` and asks `shouldClear` on
/// every change.
///
/// The appearance preference is deliberately *not* cleared: light or dark is
/// a fact about the device and the person holding it, not about the account.
nonisolated enum SessionCleanup {
    /// Whether moving from `previous` to `current` ends a session.
    ///
    /// - `nil → uid` is launch restoring a session, or a sign-in: nothing to
    ///   clear, and clearing would wipe the returning account's own history.
    /// - `uid → nil` is a sign-out (or a revoked or deleted session).
    /// - `uid → other uid` is an account swap without a sign-out in between.
    static func shouldClear(previous: String?, current: String?) -> Bool {
        guard let previous else { return false }
        return previous != current
    }

    /// Clears the `UserDefaults`-backed stores that have no live instance to
    /// tell. Each reads through to `defaults` on every access, so removing
    /// the key is enough. (`RecentCourtsStore` publishes a cached copy, so
    /// the app clears its own instance instead.)
    @MainActor
    static func clearDismissalsAndCelebrations(defaults: UserDefaults = .standard) {
        InboxDismissalsStore(defaults: defaults).clear()
        CelebratedWinsStore(defaults: defaults).clear()
    }
}
