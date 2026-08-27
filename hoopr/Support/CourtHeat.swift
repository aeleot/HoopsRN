import SwiftUI

/// Colours a court's map pin by how busy it is **today**, so the map answers
/// "where's actually happening" at a glance rather than just "where are the
/// courts".
///
/// Five fixed stops, one per game count from none to a lot, all one family:
/// the brand orange for a court with nothing scheduled, then darkening and
/// reddening in even steps to a saturated reddish orange for the busiest tier.
///
/// **The scale starts at the brand orange rather than below it.** It used to
/// open on a near-white cream (`FDECD8`) so a quiet court receded into the
/// basemap; anchoring stop 0 on `hooprOrange`'s light value instead makes an
/// unbooked court read as a *court* first and a quiet one second. The cost is
/// real and worth knowing: the whole ramp now lives in the top half of the
/// old lightness range, so "nothing today" and "one game" are one step apart
/// in darkness rather than the pale-to-saturated jump they used to be.
///
/// Fixed rather than routed through `Theme.swift`'s light/dark provider on
/// purpose — this is a data scale read against the map's own muted basemap in
/// both appearances, not app chrome that should invert with the system
/// setting. Stop 0 therefore hardcodes `hooprOrange`'s **light** value rather
/// than referencing the role: the role itself stays exactly where it is, and
/// this palette stays a separate, deliberately literal one. If the brand
/// orange is ever retuned, this stop does not follow on its own.
///
/// `MapTab` / `FindAMatchViewModel` compute *what* to feed this — the count of
/// games scheduled at a court today, from the same `queuedGames` +
/// `publicGames` the app already holds, so this needs no new read and no rules
/// change. `MapView` is the only caller, and since clustering was dropped
/// there is exactly one kind of lookup: a single court's marker looking up its
/// own count. One pin, one court, one number.
enum CourtHeat {
    /// Index *n* is the colour for exactly *n* games today; the last stop is
    /// also the ceiling for everything at or above it. Five stops because five
    /// were specified — widen this array to add finer tiers, the lookup
    /// doesn't care how many there are.
    ///
    /// The three middle stops are a straight linear RGB interpolation between
    /// the two ends, which lands them on roughly even perceived-brightness
    /// steps (~15 points of luma apiece) and a hue walking 17° → 5°. Keep that
    /// property if you retune: uneven steps read as "these two mean the same
    /// thing" even when the counts differ.
    ///
    /// **Retuned on 2026-08-22** alongside `hooprOrange`'s move to `#EE6730`.
    /// The busiest stop was rederived at the same ratio to the new stop 0 that
    /// the old ceiling held to the old stop 0 (R ×0.80, G ×0.31, B ×0.33), so
    /// the ramp keeps darkening *and* reddening by the same proportions —
    /// it just starts from a redder brand colour, so it ends redder too.
    private static let stops: [Color] = [
        Color(red: 0xEE / 255, green: 0x67 / 255, blue: 0x30 / 255), // EE6730 — hooprOrange's light value, nothing today
        Color(red: 0xE2 / 255, green: 0x55 / 255, blue: 0x28 / 255), // E25528
        Color(red: 0xD7 / 255, green: 0x44 / 255, blue: 0x20 / 255), // D74420
        Color(red: 0xCB / 255, green: 0x32 / 255, blue: 0x18 / 255), // CB3218
        Color(red: 0xBF / 255, green: 0x20 / 255, blue: 0x10 / 255), // BF2010 — deep red, busiest tier
    ]

    /// The top tier a court can reach — four or more games today all read the
    /// same deep red. Exposed so callers can explain the scale rather than
    /// re-deriving `stops.count`.
    static let maxTier = stops.count - 1

    /// - Parameter gameCount: How many games are scheduled at that court for
    ///   the day in question. Negative values clamp to the quietest stop rather
    ///   than trapping — nothing produces one today, but a lookup table should
    ///   never crash on a bad index.
    static func color(forGameCount gameCount: Int) -> Color {
        stops[min(max(gameCount, 0), maxTier)]
    }
}
