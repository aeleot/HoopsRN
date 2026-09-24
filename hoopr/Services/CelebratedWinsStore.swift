import Foundation

/// The wins this device has already celebrated, by season-game ID — so the
/// confetti on a confirmed win fires **once**, not every time the result is
/// opened or the screen re-renders (UI revamp Phase 5).
///
/// On-device for the reason `RecentCourtsStore` is: it records what *this
/// phone* has shown, which means nothing anywhere else and isn't worth a
/// document. A second device celebrates the same win once more; that's the
/// right answer, since the person hasn't seen it there.
final class CelebratedWinsStore {
    /// A season is tens of games; this is a long way past one, and a win older
    /// than `ResultViewModel.celebrationWindow` is never celebrated anyway, so
    /// forgetting the oldest costs nothing.
    static let maxEntries = 50

    private let defaults: UserDefaults
    private let storageKey = "celebratedWinGameIds"

    /// `defaults` is injectable so tests can run against a scratch suite
    /// instead of the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ gameId: String) -> Bool {
        ids.contains(gameId)
    }

    /// Most recent first; a repeat moves to the front rather than duplicating.
    func record(_ gameId: String) {
        var updated = ids
        updated.removeAll { $0 == gameId }
        updated.insert(gameId, at: 0)
        defaults.set(Array(updated.prefix(Self.maxEntries)), forKey: storageKey)
    }

    private var ids: [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }
}
