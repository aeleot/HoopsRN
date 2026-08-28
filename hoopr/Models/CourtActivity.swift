import Foundation

/// What's happening at a court **today**.
///
/// `Court` can't answer this. Courts ship in a bundled JSON file built from
/// OpenStreetMap; runs live in Firestore. Anything asking "is there a game on
/// here" is a join across those two sources, and this is the joined half handed
/// to whoever needs it.
///
/// Always constructible, including for a court with nothing scheduled
/// (`.quiet`), so every predicate over it is total — no optionals, and no
/// "unknown" third state for a call site to forget to handle.
nonisolated struct CourtActivity: Equatable, Sendable {
    /// Today's runs at this court, soonest first, as
    /// `FindAMatchViewModel.gamesByCourt(queued:published:)` produced them.
    ///
    /// Scoped to what the signed-in account is already allowed to see: the two
    /// listeners behind it are the user's own runs and the public ones, so
    /// nothing here can reveal a private run they aren't part of.
    let games: [Game]

    /// A court with nothing on. The default every filter is evaluated against
    /// when a court has no entry in the join.
    static let quiet = CourtActivity(games: [])

    var hasGameToday: Bool { !games.isEmpty }

    /// At least one run here you could actually walk into.
    ///
    /// `Game.openSlots` clamps at zero, so a hand-edited over-full roster reads
    /// as closed rather than going negative and looking joinable.
    var hasOpenSpot: Bool { games.contains { $0.openSlots > 0 } }
}
