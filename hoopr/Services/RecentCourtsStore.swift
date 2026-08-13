import Combine
import Foundation

/// Courts the player has opened recently, most recent first.
///
/// Deliberately on-device rather than in Firestore: recents are disposable,
/// meaningful only on the phone they happened on, and not worth a document
/// read on every launch. Favourites are the thing that syncs — see
/// `UserProfileService.setFavorite(courtId:isFavorite:)`.
final class RecentCourtsStore: ObservableObject {
    @Published private(set) var recentCourtIds: [String] = []

    /// Deep enough to be useful, shallow enough that the list stays a shortcut
    /// rather than a second search.
    static let maxEntries = 10

    private let defaults: UserDefaults
    private let storageKey = "recentCourtIds"

    /// `defaults` is injectable so tests can run against a scratch suite
    /// instead of the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentCourtIds = defaults.stringArray(forKey: storageKey) ?? []
    }

    /// Moves a court to the front, whether or not it was already present.
    func record(courtId: String) {
        var ids = recentCourtIds
        ids.removeAll { $0 == courtId }
        ids.insert(courtId, at: 0)
        recentCourtIds = Array(ids.prefix(Self.maxEntries))
        defaults.set(recentCourtIds, forKey: storageKey)
    }

    func clear() {
        recentCourtIds = []
        defaults.removeObject(forKey: storageKey)
    }
}
