import SwiftUI

/// The rule that turns a court's game count **today** into a heat tier, and the
/// only thing views and the map call to colour "how busy is it".
///
/// It answers "where's actually happening" at a glance rather than just "where
/// are the courts": five tiers, one per game count from none to a lot, all one
/// family — the brand orange for a court with nothing scheduled, darkening and
/// reddening in even steps to a saturated reddish orange for the busiest.
///
/// **This type is the rule; `Theme.swift` owns the colours.** The five fills and
/// the label that reads on each used to live here as literals. They are the
/// `hooprHeat(tier:)` and `hooprOnHeat(tier:)` roles now — see there for why the
/// palette is fixed rather than appearance-aware, why stop 0 hardcodes the
/// brand orange's light value, and why a fill and its label are one table. What
/// stays here is the part that isn't a colour: how a count becomes a tier, and
/// where the ramp tops out. Views name this, not the roles, so "how busy is this
/// court" has one definition whether it is a map pin or a dot on Home.
///
/// **The scale starts at the brand orange rather than below it.** It used to
/// open on a near-white cream so a quiet court receded into the basemap;
/// anchoring stop 0 on `hooprOrange` instead makes an unbooked court read as a
/// *court* first and a quiet one second. The cost is real: "nothing today" and
/// "one game" are one step apart in darkness.
///
/// `MapTab` / `MapViewModel` compute *what* to feed this — the count of
/// runs still on the board at a court today, from the same `queuedGames` + `publicGames`
/// the app already holds, so this needs no new read and no rules change.
/// `MapView` and Home's hot list are the callers, and since clustering was
/// dropped there is exactly one kind of lookup: a single court's own count.
enum CourtHeat {
    /// The top tier a court can reach — four or more games today all read the
    /// same deep red. Exposed so callers can explain the scale rather than
    /// re-deriving the stop count.
    static let maxTier = Color.hooprHeatMaxTier

    /// How many runs today make a court **busy** enough to glow (UI revamp
    /// Phase 5). The top two tiers, not every court with a run: on Home's list
    /// every row has at least one, and a glow on all of them would say nothing
    /// about any. One number for the map and Home, so a court that glows on one
    /// glows on the other.
    static let glowsFrom = 3

    static func glows(forGameCount gameCount: Int) -> Bool {
        gameCount >= glowsFrom
    }

    /// Negative counts clamp to the quietest tier rather than trapping — nothing
    /// produces one today, but a lookup should never crash on a bad index.
    static func tier(forGameCount gameCount: Int) -> Int {
        min(max(gameCount, 0), maxTier)
    }

    /// The fill for a court with `gameCount` games scheduled for the day in
    /// question.
    static func color(forGameCount gameCount: Int) -> Color {
        .hooprHeat(tier: tier(forGameCount: gameCount))
    }

    /// The label that reads on `color(forGameCount:)` — the pin's count. Not
    /// `hooprOnBrand`: black is 4.01:1 and 3.43:1 on the two deepest tiers.
    static func labelColor(forGameCount gameCount: Int) -> Color {
        .hooprOnHeat(tier: tier(forGameCount: gameCount))
    }
}
