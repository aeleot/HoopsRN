import Foundation

/// The wins this device has already celebrated, by season-game ID — so the
/// confetti on a confirmed win fires **once**, not every time the result is
/// opened or the screen re-renders (UI revamp Phase 5).
///
/// On-device for the reason `RecentCourtsStore` is: it records what *this
/// phone* has shown, which means nothing anywhere else and isn't worth a
/// document. A second device celebrates the same win once more; that's the
/// right answer, since the person hasn't seen it there. The storage itself is
/// `RecentKeysStore`.
final class CelebratedWinsStore: RecentKeysStore {
    /// A season is tens of games; this is a long way past one, and a win older
    /// than `ResultViewModel.celebrationWindow` is never celebrated anyway, so
    /// forgetting the oldest costs nothing.
    static let maxEntries = 50

    init(defaults: UserDefaults = .standard) {
        super.init(storageKey: "celebratedWinGameIds", capacity: Self.maxEntries, defaults: defaults)
    }
}
