import Foundation

/// The chips shown above the map. Each one narrows both the pins and the list.
///
/// **These are activity predicates now, not amenity ones.** The tab's job is
/// "find a game right now", so two of the three read today's runs at a court
/// rather than a field in `courts.json`. That's why `matches` takes a
/// `CourtActivity`: bundled geography can't answer whether anyone is playing.
///
/// The amenity chips they replaced were actively destructive. `isLit` is null
/// for 193 of the 214 courts and an absent tag means "unknown", which these
/// filters exclude — so tapping "Lit" hid 95% of the map, and "2+ hoops" (null
/// for 175) hid most of the rest. Filtering a map down to nothing is worse than
/// not offering the filter. They can come back when the dataset supports them;
/// the honest fix there is coverage, not UI.
///
/// One enum rather than a court/activity split. A split would need a merged
/// `allCases`, a sum type at the chip row, the `Set` and the predicate loop —
/// ceremony at three call sites for no behavioural gain, because
/// `CourtActivity.quiet` makes the context free at every one of them.
nonisolated enum CourtFilter: String, CaseIterable, Identifiable, Sendable {
    /// At least one run scheduled here today.
    case gamesToday
    /// At least one run here with room left.
    case openSpots
    /// `Court.access == .public`. The only pure-geography case left, and the
    /// only amenity field the dataset populates well — 172 of 214 courts.
    case openToAll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gamesToday: "Games today"
        case .openSpots:  "Open spots"
        // **Not** "Public". `Game.visibilityText` already renders "Public" and
        // "Invite only" for a run's *visibility*, and those cards sit two rows
        // below this chip. The same word meaning two different things one row
        // apart is how a vocabulary rots.
        case .openToAll:  "Open to all"
        }
    }

    var symbolName: String {
        switch self {
        case .gamesToday: "flame.fill"
        case .openSpots:  "person.badge.plus"
        case .openToAll:  "figure.walk"
        }
    }

    /// Pure and total.
    ///
    /// `activity` is `.quiet` for a court with nothing scheduled, so there's no
    /// optional to unwrap and no case that can trap on missing data — unlike
    /// the amenity filters this replaced, where an absent tag was a third state
    /// every predicate had to decide about.
    ///
    /// Note `openSpots` implies `gamesToday`: a court with no runs has no open
    /// spots, so selecting both is the same as selecting `openSpots` alone.
    /// That's correct rather than a special case — "open spots" means "a run I
    /// can join", not "an empty court".
    func matches(_ court: Court, activity: CourtActivity) -> Bool {
        switch self {
        case .gamesToday: return activity.hasGameToday
        case .openSpots:  return activity.hasOpenSpot
        case .openToAll:  return court.access == .public
        }
    }
}
