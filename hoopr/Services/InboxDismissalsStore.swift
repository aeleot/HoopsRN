import Foundation

/// The inbox cards this device has cleared, by key — so an "accepted your
/// request" card, which asks nothing of you, can be swiped away and stay gone.
///
/// On-device for the reason `CelebratedWinsStore` is: it records what *this
/// phone* has shown, and the card ages out of the inbox on its own after
/// `FriendsViewModel.acceptanceWindow` anyway. A second device showing it once
/// more is the right answer, since the person hasn't seen it there. The
/// storage itself is `RecentKeysStore`.
final class InboxDismissalsStore: RecentKeysStore {
    /// Far past how many acceptances land inside the window; the oldest are
    /// the ones already aged out, so forgetting them costs nothing.
    static let maxEntries = 100

    init(defaults: UserDefaults = .standard) {
        super.init(storageKey: "dismissedInboxCardKeys", capacity: Self.maxEntries, defaults: defaults)
    }
}
