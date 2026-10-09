import Foundation

/// The inbox cards this device has cleared, by key — so an "accepted your
/// request" card, which asks nothing of you, can be swiped away and stay gone.
///
/// On-device for the reason `CelebratedWinsStore` is: it records what *this
/// phone* has shown, and the card ages out of the inbox on its own after
/// `FriendsViewModel.acceptanceWindow` anyway. A second device showing it once
/// more is the right answer, since the person hasn't seen it there.
final class InboxDismissalsStore {
    /// Far past how many acceptances land inside the window; the oldest are
    /// the ones already aged out, so forgetting them costs nothing.
    static let maxEntries = 100

    private let defaults: UserDefaults
    private let storageKey = "dismissedInboxCardKeys"

    /// `defaults` is injectable so tests can run against a scratch suite
    /// instead of the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var keys: Set<String> {
        Set(ids)
    }

    /// Most recent first; a repeat moves to the front rather than duplicating.
    func record(_ key: String) {
        var updated = ids
        updated.removeAll { $0 == key }
        updated.insert(key, at: 0)
        defaults.set(Array(updated.prefix(Self.maxEntries)), forKey: storageKey)
    }

    private var ids: [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }
}
