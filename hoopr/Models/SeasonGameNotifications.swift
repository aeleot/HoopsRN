import Foundation

/// Which local notifications a scheduled match needs, and everything about
/// them — with no `UserNotifications` in sight.
///
/// **The split is the whole design.** `UNUserNotificationCenter` cannot be
/// tested here, and the *decision* about what to schedule is the part that can
/// be wrong in a way nobody notices: a notification that fires at the wrong
/// hour, or an identifier that duplicates instead of replacing. So every
/// decision lives here, as a pure function over plain values, in the
/// `MatchRules` / `Game.validate` tradition — `now`-injectable, no service, no
/// main actor. `NotificationService` executes whatever this returns and
/// decides nothing on its own.
nonisolated enum SeasonGameNotifications {

    /// One notification this game needs, fully formed.
    struct Planned: Equatable, Sendable {
        /// `"seasonGame:{id}:{kind}"`. Built only from the game's own
        /// immutable document ID and a fixed `Kind` — never from
        /// `fireDate` or anything else that could change. That's what makes a
        /// re-plan for the same game **replace** these three requests rather
        /// than pile a fourth and fifth alongside them: the identifier a
        /// second call produces is bit-for-bit the one a first call produced,
        /// so `NotificationService`'s remove-then-add lands on the same slot.
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Which trigger a planned notification is for. Raw values are the
    /// identifier's suffix, so changing one changes the other — there is only
    /// one place this string is spelled.
    enum Kind: String, CaseIterable {
        case reminder   // T-60
        case tipoff     // T-0
        case recap      // T+90
    }

    /// How long before tip-off the reminder fires. Plan §4.
    static let reminderLead: TimeInterval = 60 * 60

    /// How long after tip-off the recap prompt fires. Plan §4. Points at a
    /// screen Phase 6 builds — shipped anyway, because the schema and the copy
    /// are already settled, and a notification added later would miss every
    /// game played between now and then.
    static let recapDelay: TimeInterval = 90 * 60

    /// Every notification `game` needs, given `now` — 0 to 3 of them,
    /// never more.
    ///
    /// **Every decision is here, including "schedule nothing."** A trigger
    /// whose fire date has already passed relative to `now` is omitted rather
    /// than handed to the service to skip — `UNUserNotificationCenter` accepts
    /// a past trigger date without complaint and fires it immediately, which
    /// would turn "you joined a match that starts in five minutes" into every
    /// notification landing on the phone at once. A cancelled match gets none
    /// at all: there is nothing left on `now` to be reminded of.
    ///
    /// - Parameters:
    ///   - game: the match. `game.scheduledTime` anchors every trigger.
    ///   - opponentName: denormalized on the game document already
    ///     (`homeSquadName`/`awaySquadName`); the caller picks the *other*
    ///     side's name via `SeasonGame.opponentName(of:)`.
    ///   - courtName: resolved from `game.courtId` by the caller.
    ///     **Not part of the schema** — a court's human name lives in the
    ///     bundled dataset, not on the match document, and this function has
    ///     no dataset to look it up in. Handing it a resolved string keeps the
    ///     *copy* itself the only decision made here, rather than splitting it
    ///     between this function and whoever calls it.
    ///   - now: injected so every branch is testable without waiting.
    static func plan(
        for game: SeasonGame,
        opponentName: String,
        courtName: String,
        now: Date = Date()
    ) -> [Planned] {
        guard game.status == .scheduled else { return [] }

        let format = game.format.displayName
        let reminderDate = game.scheduledTime.addingTimeInterval(-reminderLead)
        let recapDate = game.scheduledTime.addingTimeInterval(recapDelay)

        var planned: [Planned] = []

        if reminderDate > now {
            planned.append(Planned(
                identifier: identifier(for: game.id, kind: .reminder),
                fireDate: reminderDate,
                title: "Game in an hour",
                body: "\(format) vs \(opponentName) in an hour — \(courtName)"
            ))
        }

        if game.scheduledTime > now {
            planned.append(Planned(
                identifier: identifier(for: game.id, kind: .tipoff),
                fireDate: game.scheduledTime,
                title: "Tip-off",
                body: "Tip-off. Tap to mark your squad as arrived."
            ))
        }

        if recapDate > now {
            planned.append(Planned(
                identifier: identifier(for: game.id, kind: .recap),
                fireDate: recapDate,
                title: "How'd it go?",
                body: "How'd it go? Record the result."
            ))
        }

        return planned
    }

    /// Every identifier a game could ever produce, planned or not — what
    /// `NotificationService` removes before adding a fresh plan, so a
    /// cancelled trigger (the game got called off, or a reminder's fire date
    /// has since passed) is actually cleared rather than left to fire stale.
    static func allIdentifiers(for gameId: String) -> [String] {
        Kind.allCases.map { identifier(for: gameId, kind: $0) }
    }

    static func identifier(for gameId: String, kind: Kind) -> String {
        "seasonGame:\(gameId):\(kind.rawValue)"
    }
}
