import Combine
import Foundation

/// Courts the player has opened recently, most recent first.
///
/// Deliberately on-device rather than in Firestore: recents are disposable,
/// meaningful only on the phone they happened on, and not worth a document
/// read on every launch. Favourites are the thing that syncs — see
/// `UserProfileService.setFavorite(courtId:isFavorite:)`.
///
/// A `RecentKeysStore` with a `@Published` mirror of its list, so the map's
/// recents row can observe it.
final class RecentCourtsStore: ObservableObject {
    @Published private(set) var recentCourtIds: [String] = []

    /// Deep enough to be useful, shallow enough that the list stays a shortcut
    /// rather than a second search.
    static let maxEntries = 10

    private let store: RecentKeysStore

    /// `defaults` is injectable so tests can run against a scratch suite
    /// instead of the real one.
    init(defaults: UserDefaults = .standard) {
        store = RecentKeysStore(storageKey: "recentCourtIds", capacity: Self.maxEntries, defaults: defaults)
        recentCourtIds = store.keys
    }

    /// Moves a court to the front, whether or not it was already present.
    func record(courtId: String) {
        recentCourtIds = store.record(courtId)
    }
}
