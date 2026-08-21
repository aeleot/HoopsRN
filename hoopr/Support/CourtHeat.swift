import SwiftUI

/// Colours a court's map pin by how busy it is **today**, so the map answers
/// "where's actually happening" at a glance rather than just "where are the
/// courts".
///
/// Five fixed stops, one per game count from none to a lot: a cool, quiet
/// light sky blue — blended roughly halfway to white, so a quiet map doesn't
/// read as loud as a busy one — for a court with nothing scheduled, climbing
/// through two close, warm ambers, and landing on a deep red for the busiest
/// tier. Fixed
/// rather than routed through `Theme.swift`'s light/dark provider on purpose —
/// this is a data scale read against the map's own muted basemap in both
/// appearances, not app chrome that should invert with the system setting. The
/// existing brand roles (`hooprOrange`/`hooprDarkOrange`) stay exactly where
/// they are; this is a separate, deliberately literal palette.
///
/// `MapTab` / `FindAMatchViewModel` compute *what* to feed this — the count of
/// games scheduled at a court today, from the same `queuedGames` +
/// `publicGames` the app already holds, so this needs no new read and no rules
/// change. `MapView` is the only caller: a single court's marker looks itself
/// up, and a cluster looks up the **sum** across every court folded into it,
/// so a bundle of quiet courts doesn't read as busy just because there are
/// several of them.
enum CourtHeat {
    /// Index *n* is the colour for exactly *n* games today; the last stop is
    /// also the ceiling for everything at or above it. Five stops because five
    /// were specified — widen this array to add finer tiers, the lookup
    /// doesn't care how many there are.
    private static let stops: [Color] = [
        Color(red: 0xC3 / 255, green: 0xE6 / 255, blue: 0xFC / 255), // light sky blue, lightened toward white — nothing today
        Color(red: 0xFF / 255, green: 0xD1 / 255, blue: 0x31 / 255), // FFD131
        Color(red: 0xF5 / 255, green: 0xB8 / 255, blue: 0x2E / 255), // F5B82E
        Color(red: 0xF4 / 255, green: 0xAC / 255, blue: 0x32 / 255), // F4AC32
        Color(red: 0xB9 / 255, green: 0x0E / 255, blue: 0x0A / 255), // deep red — matches hooprRed's light value
    ]

    /// The top tier a court can reach — four or more games today all read the
    /// same deep red. Exposed so callers can explain the scale rather than
    /// re-deriving `stops.count`.
    static let maxTier = stops.count - 1

    /// - Parameter gameCount: How many games are scheduled at a court (or, for
    ///   a cluster, summed across every court it bundles) for the day in
    ///   question. Negative values clamp to the quietest stop rather than
    ///   trapping — nothing produces one today, but a lookup table should never
    ///   crash on a bad index.
    static func color(forGameCount gameCount: Int) -> Color {
        stops[min(max(gameCount, 0), maxTier)]
    }
}
