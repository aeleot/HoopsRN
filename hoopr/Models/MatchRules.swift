import CoreLocation
import Foundation

/// One legal, ranked match: which ticket, where, when, and how good.
///
/// `courtId` and `scheduledTime` are **derived** rather than negotiated — both
/// clients compute the same answer from the same inputs, so there is no
/// round trip to agree on. The agreement isn't the guarantee, though: the
/// `seasonGames` create rule verifies the court is in the home ticket's own
/// `courtIds` and the time falls inside its window, so a modified client
/// cannot schedule you somewhere you never said you'd go.
nonisolated struct MatchCandidate: Identifiable, Sendable, Equatable {
    /// The opponent's ticket — the one that would be claimed, which makes its
    /// squad the *home* side.
    let ticket: MatchTicket
    let courtId: String
    let scheduledTime: Date
    /// Higher is better. Comparable only against candidates produced from the
    /// same `mine` and `now`.
    let score: Double

    var id: String { ticket.id }
}

/// Everything about whether two tickets should play each other, with no
/// Firestore in sight.
///
/// **This is the one piece of Seasons whose correctness cannot be checked by
/// looking at a screen.** A subtly wrong score produces a *plausible* match,
/// not a visible bug — an opponent across town when one was two blocks away,
/// a mismatch that reads as bad luck. So it is a pure function over plain
/// values, in the `Game.validate` / `CourtSearch` tradition: `now`-injectable,
/// no service, no main actor, and the single source of truth that both the
/// scan and the tests read.
///
/// Two categories of rule:
///
/// - **Hard rules** reject outright. A hard rule is one where the match is
///   impossible or illegal, not merely worse: the squads share a player, the
///   formats differ, the windows don't hold a game. There is no "poor but
///   acceptable" version of any of them.
/// - **Soft rules** are weighted into `score`. Each is a continuum, and each
///   distinguishes one *legal* match from another.
///
/// **Relaxation** is a single `Double` in `0...1` derived from the age of *my*
/// ticket. It widens three things — how far one of their courts may be from my
/// anchor, how mismatched the records may be, and how much comfort margin the
/// window needs beyond the game itself. It **never** widens roster
/// disjointness, format or region equality, expiry, the minimum lead time, the
/// game fitting inside the overlap, or the requirement that the court come from
/// the home ticket's own list. Those last are correctness and server-side
/// checks; relaxing them client-side would only produce writes the rules
/// refuse.
nonisolated enum MatchRules {

    // MARK: - Tuning

    /// How long a ticket waits before its criteria are fully relaxed.
    ///
    /// Ten minutes: long enough that a healthy pool matches on its own terms
    /// first, short enough that a thin one doesn't leave someone staring at a
    /// spinner. The UI says "Widening the search…" out loud when this starts to
    /// bite, because a search that silently lowered its standards would produce
    /// a mismatch the user can't explain.
    static let fullRelaxation: TimeInterval = 10 * 60

    /// How far, in miles, one of *their* courts may be from my anchor when it
    /// isn't on my own list.
    ///
    /// **Zero at relaxation 0**, which is what makes the unrelaxed rule a
    /// straight intersection of the two court lists: at t=0 the only acceptable
    /// courts are ones I named myself. Twenty-five miles at full relaxation is
    /// past the dataset's own span, so a thin pool is never blocked on
    /// geography alone.
    static let relaxedRadiusMiles: ClosedRange<Double> = 0...25

    /// How far apart two win percentages may be.
    ///
    /// A note on where this comes from, because the design read two ways: it
    /// lists record proximity only under *soft* rules, but its relaxation
    /// paragraph names "the record-proximity tolerance" as something relaxation
    /// widens — and a tolerance nothing enforces isn't a tolerance. It is
    /// implemented as a gate, deliberately generous: 0.35 apart at relaxation 0
    /// (a .700 squad won't be handed a .300 one immediately) and fully open at
    /// relaxation 1. So it changes *when* an uneven match happens, never
    /// *whether* — which is the reading that leaves both sentences true.
    static let recordTolerance: ClosedRange<Double> = 0.35...1.0

    /// Imagined games added to every record before it is compared — half won,
    /// half lost — so a short record reads as the little evidence it is.
    ///
    /// **A raw win percentage treats one game as a verdict.** A squad's first
    /// loss took it from .500 to .000, the widest gap there is, and held it
    /// out of the pool for minutes behind every unplayed squad — on the
    /// strength of one result. With four imagined games 0–1 reads as .400,
    /// one game off an unplayed squad, and it matches at once. A long record
    /// barely moves (10–0 reads as .857), so a real mismatch is still held
    /// back by `recordTolerance`.
    ///
    /// Comparison only. The record a squad sees is still its real W–L.
    static let recordPriorGames = 4

    /// A squad's win percentage for comparison, shrunk toward .500 by
    /// `recordPriorGames`.
    ///
    /// An unplayed squad reads as exactly `0.5`, as `SeasonGame.Record` does,
    /// rather than zero: treating "no record" as "loses everything" would rank
    /// every new squad against the worst opponents in the pool.
    static func recordRating(for ticket: MatchTicket) -> Double {
        let prior = Double(recordPriorGames)
        return (Double(ticket.wins) + prior / 2) / (Double(ticket.wins + ticket.losses) + prior)
    }

    /// Slack the window must carry *beyond* the game itself, so two squads
    /// aren't scheduled into the exact minute they both stop being free.
    ///
    /// Thirty minutes at relaxation 0, nothing at relaxation 1. **It never goes
    /// negative**: the overlap must always hold a whole game, at every
    /// relaxation value, or the match is one that can't be played.
    static let comfortMargin: ClosedRange<TimeInterval> = 0...(30 * 60)

    /// Tip-off lands on a multiple of this, measured in **absolute seconds
    /// since the epoch**.
    ///
    /// Absolute, not since local midnight, and that is the whole point: two
    /// clients in different time zones, or the same client either side of a
    /// daylight-saving change, compute the identical instant. A grain anchored
    /// to a local calendar would drift by the offset and put the two squads at
    /// the court an hour apart.
    static let schedulingGrain: TimeInterval = 15 * 60

    /// What each soft signal is worth. They sum to 1, so a score is always in
    /// `0...1` and two candidates are comparable by construction.
    ///
    /// Record proximity leads because competitive balance is what makes a
    /// season feel fair — it's the direct GameKit analogue, and the hook a real
    /// skill rating would plug into later. Travel is second because a match
    /// nobody drives to isn't a match. Their ticket's age is third and is pure
    /// fairness: a squad that has waited longer gets picked first. Overlap size
    /// is last and is a tiebreaker — more room to schedule is better, but only
    /// once everything else is equal.
    enum Weight {
        static let record = 0.35
        static let travel = 0.30
        static let waiting = 0.20
        static let overlap = 0.15
    }

    // MARK: - Relaxation

    /// How relaxed my search is, from my own ticket's age. `0` at the moment I
    /// queue, `1` once I've waited `fullRelaxation`.
    ///
    /// Derived from **my** ticket, not theirs: it's my patience being spent, so
    /// it's my standards that widen. Theirs contributes to the score through
    /// the waiting-fairness signal instead.
    static func relaxation(for mine: MatchTicket, now: Date) -> Double {
        guard fullRelaxation > 0 else { return 1 }
        return min(1, max(0, mine.age(at: now) / fullRelaxation))
    }

    /// Linear interpolation across a bound, clamped. The single shape every
    /// relaxed bound uses, so none of them can widen on a different curve by
    /// accident.
    private static func widened(_ bound: ClosedRange<Double>, by relaxation: Double) -> Double {
        let t = min(1, max(0, relaxation))
        return bound.lowerBound + (bound.upperBound - bound.lowerBound) * t
    }

    static func radiusMiles(at relaxation: Double) -> Double {
        widened(relaxedRadiusMiles, by: relaxation)
    }

    static func recordTolerance(at relaxation: Double) -> Double {
        widened(recordTolerance, by: relaxation)
    }

    /// Shrinks as relaxation grows — the one bound that narrows, because the
    /// margin is a *requirement* rather than a permission.
    static func comfortMargin(at relaxation: Double) -> TimeInterval {
        let t = min(1, max(0, relaxation))
        return comfortMargin.upperBound + (comfortMargin.lowerBound - comfortMargin.upperBound) * t
    }

    // MARK: - Re-scanning as relaxation widens

    /// How often a scan that found nothing looks again while my criteria are
    /// still widening.
    ///
    /// **Relaxation only helps if somebody re-ranks the pool.** It is derived
    /// from my ticket's age, and ageing is not a Firestore event — no snapshot
    /// fires because a minute passed. A scan that came up empty used to be the
    /// last scan until the pool itself changed, so two squads queued a few
    /// seconds apart with no court in common (or a window too tight for the
    /// unrelaxed comfort margin) sat in each other's pool forever, under a card
    /// that read "Widening the search" and "1 other squad queued nearby".
    ///
    /// Fifteen seconds: the radius grows 2.5 miles a minute, so a finer poll
    /// would re-rank against criteria that have barely moved. The re-scan is
    /// pure arithmetic over the pool already in memory — no read — so this is
    /// latency tuning, not cost tuning.
    static let relaxationRescanInterval: TimeInterval = 15

    /// How long to wait before re-ranking a pool that just produced no
    /// candidate, or `nil` when waiting cannot change the answer.
    ///
    /// Waiting helps only while both of these hold:
    /// - **someone else is in the pool.** An empty pool changes by a snapshot,
    ///   and the listener already re-scans on every one.
    /// - **my criteria can still widen.** Past `fullRelaxation` every relaxed
    ///   bound is at its limit, and the rules that stay — expiry, lead time, the
    ///   game fitting before the overlap closes — only get *harder* to meet as
    ///   time passes. A pool rejected at full relaxation is rejected for good
    ///   until it changes, and the listener covers that.
    static func rescanDelay(
        for mine: MatchTicket,
        pool: [MatchTicket],
        now: Date
    ) -> TimeInterval? {
        guard pool.contains(where: { $0.squadId != mine.squadId }) else { return nil }
        guard relaxation(for: mine, now: now) < 1 else { return nil }
        return relaxationRescanInterval
    }

    // MARK: - The rule set

    /// Whether `theirs` is a match for `mine`, and if so where, when, and how
    /// good.
    ///
    /// - Parameters:
    ///   - mine: my squad's ticket. Its age sets the relaxation.
    ///   - theirs: the pool ticket being considered. Claiming it makes their
    ///     squad the **home** side, which is why the court is drawn from their
    ///     list.
    ///   - courts: the bundled dataset, keyed by ID, for distances.
    ///   - anchor: where distances are measured from — `LocationService.homeLocation`,
    ///     like every other distance in the app.
    ///   - now: injected so every branch is testable without waiting.
    /// - Returns: the candidate, or `nil` if any hard rule rejects.
    static func candidate(
        for mine: MatchTicket,
        against theirs: MatchTicket,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D,
        now: Date
    ) -> MatchCandidate? {
        let relaxation = relaxation(for: mine, now: now)

        // ---- Hard rules ----

        // A squad can't play itself, and — the one most likely to be quietly
        // dropped — neither can two squads sharing a player. Checked before
        // anything else because it's the only rule here that stays true at
        // every relaxation value, forever.
        guard mine.squadId != theirs.squadId else { return nil }
        guard !mine.sharesPlayer(with: theirs) else { return nil }

        // Different pools by construction. The Firestore query already filters
        // on both, so this is the client agreeing with the query rather than
        // duplicating it — and it's what keeps the function correct when it's
        // handed a pool from anywhere.
        guard mine.format == theirs.format else { return nil }
        guard mine.region == theirs.region else { return nil }

        guard !mine.isExpired(at: now), !theirs.isExpired(at: now) else { return nil }
        guard theirs.isClaimable(at: now) else { return nil }

        // My own ticket has to still be in play. A ticket leaves the pool
        // exactly once, so if mine is already spent I'm in a match and must not
        // take anyone else out of the pool — that's how a squad double-books
        // itself. The server enforces the same thing from the other side: the
        // commit's rules only permit `open` -> `matched`.
        guard mine.isClaimable(at: now) else { return nil }

        guard let overlap = mine.overlap(with: theirs) else { return nil }

        let duration = mine.format.duration
        let required = duration + comfortMargin(at: relaxation)
        guard overlap.duration >= required else { return nil }

        // Record proximity — see `recordTolerance` for why this is a gate, and
        // `recordPriorGames` for why it isn't the raw win percentage.
        let recordGap = abs(recordRating(for: mine) - recordRating(for: theirs))
        guard recordGap <= recordTolerance(at: relaxation) else { return nil }

        guard let court = court(
            forHome: theirs, guest: mine, courts: courts, anchor: anchor, relaxation: relaxation
        ) else { return nil }

        guard let scheduledTime = scheduledTime(in: overlap, duration: duration, now: now) else {
            return nil
        }

        // ---- Soft rules ----

        let travelMiles = courts[court].map {
            Distance.miles(Distance.between(anchor, $0.coordinate))
        } ?? 0

        let score =
            Weight.record * (1 - min(1, recordGap))
            + Weight.travel * (1 - min(1, travelMiles / relaxedRadiusMiles.upperBound))
            + Weight.waiting * min(1, theirs.age(at: now) / fullRelaxation)
            + Weight.overlap * min(1, overlap.duration / (duration * 2))

        return MatchCandidate(
            ticket: theirs,
            courtId: court,
            scheduledTime: scheduledTime,
            score: score
        )
    }

    /// Every legal match in a pool, best first.
    ///
    /// Ties break on squad ID rather than on pool order: a Firestore snapshot's
    /// order is not something to rank on, and without a second key two clients
    /// scanning the same pool could pick different top candidates and claim
    /// past each other.
    static func rank(
        for mine: MatchTicket,
        against pool: [MatchTicket],
        courts: [String: Court],
        anchor: CLLocationCoordinate2D,
        now: Date
    ) -> [MatchCandidate] {
        pool
            .compactMap { candidate(for: mine, against: $0, courts: courts, anchor: anchor, now: now) }
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.ticket.squadId < rhs.ticket.squadId
                    : lhs.score > rhs.score
            }
    }

    // MARK: - Derivation

    /// The court a match lands at: the **home** ticket's highest-preference
    /// court that the guest will accept.
    ///
    /// Always from `home.courtIds`, at every relaxation value, because that is
    /// exactly what the `seasonGames` create rule checks. A court the guest
    /// listed but the home squad didn't would be refused server-side, so
    /// offering one here would turn a legal-looking match into a
    /// `permission-denied`.
    ///
    /// Acceptance to the guest widens with relaxation, and only that:
    /// - on the guest's own list — acceptable immediately, at any relaxation;
    /// - otherwise — acceptable once it's within `radiusMiles(at:)` of the
    ///   anchor, which is **zero** at relaxation 0. So the unrelaxed rule is a
    ///   straight list intersection, exactly as the plan states.
    ///
    /// Preference is the home list's own order. A court missing from the
    /// dataset can still be chosen when both squads named it — they know where
    /// they're going even if this build's `courts.json` doesn't.
    static func court(
        forHome home: MatchTicket,
        guest: MatchTicket,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D,
        relaxation: Double
    ) -> String? {
        let guestCourts = Set(guest.courtIds)
        let radius = radiusMiles(at: relaxation)

        return home.courtIds.first { courtId in
            if guestCourts.contains(courtId) { return true }
            guard radius > 0, let court = courts[courtId] else { return false }
            return Distance.miles(Distance.between(anchor, court.coordinate)) <= radius
        }
    }

    /// Tip-off: the earliest instant inside `overlap` that clears the minimum
    /// lead time, rounded up to `schedulingGrain`, with the whole game still
    /// fitting before the overlap ends.
    ///
    /// Rounding up rather than to the nearest grain is deliberate — rounding
    /// down could land inside the lead-time cushion the rounding was applied
    /// after, which is the sort of off-by-one that only shows up as a rejected
    /// write.
    static func scheduledTime(
        in overlap: DateInterval,
        duration: TimeInterval,
        now: Date
    ) -> Date? {
        let earliest = max(overlap.start, now.addingTimeInterval(Game.minimumLeadTime))
        let start = roundedUpToGrain(earliest)

        guard start >= overlap.start else { return nil }
        guard start.addingTimeInterval(duration) <= overlap.end else { return nil }
        // Re-checked after rounding: the grain can only push the time later, but
        // "later" has to stay in the future by more than the lead time, and
        // saying so costs one line against a rule the server enforces.
        guard start >= now.addingTimeInterval(Game.minimumLeadTime) else { return nil }

        return start
    }

    /// The next multiple of `schedulingGrain` at or after `date`, in seconds
    /// since the epoch.
    ///
    /// No `Calendar`, deliberately. Absolute arithmetic is what makes two
    /// clients agree across time zones, across midnight, and across a
    /// daylight-saving change — none of which alters the number of seconds
    /// between two instants.
    static func roundedUpToGrain(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        let grains = (seconds / schedulingGrain).rounded(.up)
        return Date(timeIntervalSince1970: grains * schedulingGrain)
    }
}
