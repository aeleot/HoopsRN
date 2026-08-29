import CoreLocation
import XCTest
@testable import hoopr

/// The heaviest suite in Seasons, and the reason `MatchRules` is a pure
/// function.
///
/// A wrong score here doesn't crash and doesn't render oddly — it produces a
/// *plausible* match. An opponent across town when one was two blocks away
/// reads as bad luck, not as a bug, and nothing on any screen would ever say
/// otherwise. So every rule is exercised in isolation, the ordering is
/// exercised as ordering, and the arithmetic is exercised at the boundaries
/// where it's actually hard: midnight, a daylight-saving change, and a claim
/// that went stale one second ago.
///
/// Everything runs without Firestore, a service, or a main actor. That's the
/// property the whole design is arranged around.
final class MatchRulesTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed instant, deliberately *not* on a 15-minute boundary so the
    /// rounding in `scheduledTime` actually has something to do.
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private let anchor = CLLocationCoordinate2D(latitude: 35.9940, longitude: -78.8986)

    /// Roughly 69 miles to a degree of latitude, so these sit at about 0, 2, 15
    /// and 35 miles from the anchor.
    private var courts: [String: Court] {
        [
            "here": court("here", latitude: 35.9940),
            "near": court("near", latitude: 35.9940 + 0.0290),
            "far": court("far", latitude: 35.9940 + 0.2170),
            "veryFar": court("veryFar", latitude: 35.9940 + 0.5000),
        ]
    }

    private func court(_ id: String, latitude: Double) -> Court {
        Court(
            id: id,
            name: "\(id) Basketball Court",
            latitude: latitude,
            longitude: -78.8986,
            address: "1 Main St",
            city: "Durham",
            hoops: 2,
            surface: "asphalt",
            isLit: nil,
            isCovered: nil,
            access: .public,
            osmType: nil,
            osmId: nil
        )
    }

    /// A ticket that matches the other default ticket. Every test starts from a
    /// pair that works and breaks exactly one thing, so a rejection can only be
    /// the rule under test.
    private func ticket(
        squadId: String,
        members: [String],
        format: SquadFormat = .threeVThree,
        region: String = "Durham",
        courtIds: [String] = ["here"],
        windowStart: TimeInterval = 3_600,
        windowEnd: TimeInterval = 4 * 3_600,
        wins: Int = 5,
        losses: Int = 5,
        status: MatchTicket.Status = .open,
        claimedBy: String? = nil,
        claimedAt: TimeInterval? = nil,
        createdAt: TimeInterval? = 0,
        expiresAt: TimeInterval = 2 * 3_600
    ) -> MatchTicket {
        MatchTicket(
            squadId: squadId,
            leaderId: "\(squadId)_leader",
            squadName: squadId.capitalized,
            memberIds: members,
            format: format,
            region: region,
            courtIds: courtIds,
            windowStart: now.addingTimeInterval(windowStart),
            windowEnd: now.addingTimeInterval(windowEnd),
            wins: wins,
            losses: losses,
            status: status,
            claimedBy: claimedBy,
            claimedAt: claimedAt.map { now.addingTimeInterval($0) },
            matchedGameId: nil,
            createdAt: createdAt.map { now.addingTimeInterval($0) },
            expiresAt: now.addingTimeInterval(expiresAt)
        )
    }

    private var mine: MatchTicket { ticket(squadId: "mine", members: ["a1", "a2", "a3"]) }
    private var theirs: MatchTicket { ticket(squadId: "theirs", members: ["b1", "b2", "b3"]) }

    private func candidate(
        _ mine: MatchTicket,
        _ theirs: MatchTicket,
        at instant: Date? = nil
    ) -> MatchCandidate? {
        MatchRules.candidate(
            for: mine,
            against: theirs,
            courts: courts,
            anchor: anchor,
            now: instant ?? now
        )
    }

    // MARK: - The happy path

    /// The baseline every rejection test is measured against. If this stops
    /// producing a candidate, every `XCTAssertNil` below starts passing for the
    /// wrong reason.
    func testTwoCompatibleTicketsProduceACandidate() throws {
        let match = try XCTUnwrap(candidate(mine, theirs))

        XCTAssertEqual(match.ticket.squadId, "theirs")
        XCTAssertEqual(match.courtId, "here")
        XCTAssertTrue((0...1).contains(match.score), "Score \(match.score) is outside 0...1")
    }

    /// Tip-off is the start of the overlap, rounded up to the scheduling grain,
    /// and always clear of the lead time the server checks.
    func testScheduledTimeLandsOnTheGrainInsideTheWindow() throws {
        let match = try XCTUnwrap(candidate(mine, theirs))

        XCTAssertEqual(
            match.scheduledTime.timeIntervalSince1970
                .truncatingRemainder(dividingBy: MatchRules.schedulingGrain),
            0,
            accuracy: 0.001,
            "Tip-off must land on a \(Int(MatchRules.schedulingGrain / 60))-minute boundary so both clients agree."
        )
        XCTAssertGreaterThanOrEqual(
            match.scheduledTime, now.addingTimeInterval(Game.minimumLeadTime)
        )
        XCTAssertGreaterThanOrEqual(match.scheduledTime, mine.windowStart)
        XCTAssertLessThanOrEqual(
            match.scheduledTime.addingTimeInterval(mine.format.duration), mine.windowEnd
        )
    }

    // MARK: - Hard rules, each on its own

    /// **The one most likely to be quietly dropped, and the reason `memberIds`
    /// is denormalized onto the ticket.** A person cannot play themselves.
    func testASharedPlayerRejects() {
        let overlapping = ticket(squadId: "theirs", members: ["b1", "a2", "b3"])

        XCTAssertNil(candidate(mine, overlapping))
    }

    /// And it stays rejected at **every** relaxation value, 1.0 included.
    /// Relaxation widens preferences; it must never widen this.
    func testASharedPlayerRejectsAtEveryRelaxationValue() {
        let overlapping = ticket(squadId: "theirs", members: ["b1", "a2", "b3"])

        for step in 0...4 {
            let fraction = Double(step) / 4
            let aged = ticket(
                squadId: "mine",
                members: ["a1", "a2", "a3"],
                createdAt: -MatchRules.fullRelaxation * fraction
            )

            XCTAssertEqual(MatchRules.relaxation(for: aged, now: now), fraction, accuracy: 0.0001)
            XCTAssertNil(
                candidate(aged, overlapping),
                "A shared player matched at relaxation \(fraction)."
            )
        }

        // Explicitly past full relaxation too — the clamp must not wrap around
        // into some other branch.
        let ancient = ticket(
            squadId: "mine", members: ["a1", "a2", "a3"], createdAt: -10 * MatchRules.fullRelaxation
        )
        XCTAssertEqual(MatchRules.relaxation(for: ancient, now: now), 1)
        XCTAssertNil(candidate(ancient, overlapping))
    }

    func testASquadCannotMatchItself() {
        XCTAssertNil(candidate(mine, mine))
    }

    /// Same squad ID but a different roster is still the same squad — the ID is
    /// the identity, and a stale denormalized roster mustn't create a way
    /// around it.
    func testTheSameSquadIdRejectsEvenWithADifferentRoster() {
        let stale = ticket(squadId: "mine", members: ["z1", "z2", "z3"])

        XCTAssertNil(candidate(mine, stale))
    }

    func testADifferentFormatRejects() {
        let fives = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], format: .fiveVFive)

        XCTAssertNil(candidate(mine, fives))
    }

    func testADifferentRegionRejects() {
        let raleigh = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], region: "Raleigh")

        XCTAssertNil(candidate(mine, raleigh))
    }

    func testAnExpiredOpponentRejects() {
        let expired = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], expiresAt: -1)

        XCTAssertNil(candidate(mine, expired))
    }

    /// My own expiry counts too. A ticket that has aged out shouldn't be
    /// claiming anyone on its way to being cleaned up.
    func testMyOwnExpiredTicketRejects() {
        let expired = ticket(squadId: "mine", members: ["a1", "a2", "a3"], expiresAt: -1)

        XCTAssertNil(candidate(expired, theirs))
    }

    /// Expiry is exclusive at the boundary: `expiresAt == now` is expired.
    func testExpiryIsExclusiveAtTheBoundary() {
        let onTheDot = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], expiresAt: 0)

        XCTAssertTrue(onTheDot.isExpired(at: now))
        XCTAssertNil(candidate(mine, onTheDot))
    }

    func testAMatchedTicketIsNotACandidate() {
        let taken = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], status: .matched)

        XCTAssertNil(candidate(mine, taken))
    }

    func testNoWindowOverlapRejects() {
        let tomorrow = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            windowStart: 24 * 3_600,
            windowEnd: 28 * 3_600,
            expiresAt: 20 * 3_600
        )

        XCTAssertNil(mine.overlap(with: tomorrow))
        XCTAssertNil(candidate(mine, tomorrow))
    }

    /// Windows that touch but don't overlap are not an overlap. A zero-length
    /// intersection can't hold a game, and treating it as one would produce a
    /// match scheduled at the instant both squads leave.
    func testTouchingWindowsAreNotAnOverlap() {
        let after = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            windowStart: 4 * 3_600,
            windowEnd: 8 * 3_600,
            expiresAt: 5 * 3_600
        )

        XCTAssertNil(mine.overlap(with: after))
        XCTAssertNil(candidate(mine, after))
    }

    /// An overlap exactly one game long fails at relaxation 0, because the
    /// comfort margin is a *requirement* there — not because the game doesn't
    /// fit.
    func testAnOverlapWithNoComfortMarginRejectsWhileUnrelaxed() {
        let tight = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            windowStart: 3_600,
            windowEnd: 3_600 + 3_600
        )

        XCTAssertEqual(mine.overlap(with: tight)?.duration, SquadFormat.threeVThree.duration)
        XCTAssertNil(candidate(mine, tight))
    }

    /// No court in common, and at relaxation 0 the radius is zero — so the
    /// unrelaxed rule is a straight list intersection, exactly as the plan
    /// states.
    func testNoSharedCourtRejectsWhileUnrelaxed() {
        let elsewhere = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["far"])

        XCTAssertEqual(MatchRules.radiusMiles(at: 0), 0)
        XCTAssertNil(candidate(mine, elsewhere))
    }

    /// A record gap wider than the unrelaxed tolerance rejects. See
    /// `MatchRules.recordTolerance` for why this is a gate at all.
    func testATooWideRecordGapRejectsWhileUnrelaxed() {
        let dominant = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], wins: 19, losses: 1)

        XCTAssertGreaterThan(
            abs(mine.winPercentage - dominant.winPercentage),
            MatchRules.recordTolerance(at: 0)
        )
        XCTAssertNil(candidate(mine, dominant))
    }

    /// A window that opens too soon to schedule anything: the whole overlap is
    /// inside the lead-time cushion.
    func testAWindowThatCannotClearTheLeadTimeRejects() {
        let imminent = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            windowStart: -3_600,
            windowEnd: 60
        )
        let alsoImminent = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            windowStart: -3_600,
            windowEnd: 60
        )

        XCTAssertNil(candidate(imminent, alsoImminent))
    }

    // MARK: - Stale claims

    /// A claim older than `staleClaim` is claimable again; a fresh one isn't.
    /// This is the recovery that makes the two-step claim-then-create design
    /// safe without `getAfter()`.
    func testAStaleClaimIsACandidateAndAFreshOneIsNot() throws {
        let stale = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: -(MatchRules.staleClaim + 1)
        )
        let fresh = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: -(MatchRules.staleClaim - 1)
        )

        XCTAssertNotNil(try XCTUnwrap(candidate(mine, stale)))
        XCTAssertNil(candidate(mine, fresh))
    }

    /// Exactly at the boundary is still fresh — the comparison is strictly
    /// greater-than, matching the rules' `request.time > claimedAt + 90s`. A
    /// disagreement here is a client claim the server refuses.
    func testTheStaleBoundaryIsExclusive() {
        let onTheDot = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: -MatchRules.staleClaim
        )

        XCTAssertFalse(onTheDot.isClaimable(at: now))
        XCTAssertNil(candidate(mine, onTheDot))
    }

    /// A `claimed` ticket whose server timestamp hasn't resolved was written
    /// seconds ago, so it is emphatically not stale. Reading a missing
    /// timestamp as "infinitely old" would let every in-flight claim be stolen.
    func testAClaimWithAnUnresolvedTimestampIsNotStale() {
        let inFlight = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: nil
        )

        XCTAssertFalse(inFlight.isClaimable(at: now))
        XCTAssertNil(candidate(mine, inFlight))
    }

    /// My own ticket being freshly claimed stops me claiming anyone else —
    /// otherwise a squad double-books itself in the seconds before its own
    /// match lands.
    func testMyOwnFreshClaimStopsMeSearching() {
        let spokenFor = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: -1
        )

        XCTAssertNil(candidate(spokenFor, theirs))
    }

    /// …and once that claim goes stale I'm back in the pool. The same 90
    /// seconds governs both sides of the race, which is what stops the two
    /// halves drifting apart.
    func testMyOwnStaleClaimLetsMeSearchAgain() throws {
        let abandoned = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            status: .claimed,
            claimedBy: "someoneElse",
            claimedAt: -(MatchRules.staleClaim + 1)
        )

        XCTAssertNotNil(try XCTUnwrap(candidate(abandoned, theirs)))
    }

    // MARK: - Relaxation over time

    /// **The relaxation case the plan is built around**: the same pair rejects
    /// at t=0 and matches at t=`fullRelaxation` — and the court chosen is in
    /// the *home* ticket's own list both times, because that's what the
    /// `seasonGames` create rule checks server-side.
    func testACourtOutOfRangeAtZeroMatchesAtFullRelaxation() throws {
        let distant = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["far"])

        XCTAssertNil(candidate(mine, distant), "Should reject before relaxation widens the radius")

        let waited = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            createdAt: -MatchRules.fullRelaxation
        )
        let match = try XCTUnwrap(candidate(waited, distant))

        XCTAssertEqual(match.courtId, "far")
        XCTAssertTrue(
            distant.courtIds.contains(match.courtId),
            "The chosen court must come from the home ticket's own list."
        )

        // And the unrelaxed pairing that *does* work also draws from the home
        // list — the invariant holds either side of the relaxation.
        let close = try XCTUnwrap(candidate(mine, theirs))
        XCTAssertTrue(theirs.courtIds.contains(close.courtId))
    }

    /// Relaxation widens the radius but never past the ceiling: a court beyond
    /// `relaxedRadiusMiles.upperBound` stays out forever.
    func testACourtBeyondTheCeilingNeverMatches() {
        let unreachable = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["veryFar"])
        let waited = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            createdAt: -10 * MatchRules.fullRelaxation
        )

        XCTAssertNil(candidate(waited, unreachable))
    }

    func testARecordGapTooWideAtZeroMatchesAtFullRelaxation() throws {
        let dominant = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], wins: 19, losses: 1)

        XCTAssertNil(candidate(mine, dominant))

        let waited = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            createdAt: -MatchRules.fullRelaxation
        )
        XCTAssertNotNil(try XCTUnwrap(candidate(waited, dominant)))
    }

    func testAWindowWithNoMarginAtZeroMatchesAtFullRelaxation() throws {
        // Deliberately grain-aligned (`now` is not), so what's under test here
        // is the comfort margin rather than the rounding — a window that ends
        // 3,600 seconds after an *unaligned* start is rejected by
        // `testRoundingPastTheFitRejects`'s rule instead, which is a different
        // and separately covered reason.
        let tight = ticket(
            squadId: "theirs",
            members: ["b1", "b2", "b3"],
            windowStart: 3_800,
            windowEnd: 3_800 + 3_600
        )

        XCTAssertEqual(
            tight.windowStart.timeIntervalSince1970
                .truncatingRemainder(dividingBy: MatchRules.schedulingGrain),
            0,
            accuracy: 0.001
        )

        XCTAssertNil(candidate(mine, tight))

        let waited = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            createdAt: -MatchRules.fullRelaxation
        )
        let match = try XCTUnwrap(candidate(waited, tight))

        // Fully relaxed still means the *whole game* fits. That bound never
        // moves, at any relaxation.
        XCTAssertLessThanOrEqual(
            match.scheduledTime.addingTimeInterval(SquadFormat.threeVThree.duration),
            tight.windowEnd
        )
    }

    /// Relaxation is a straight ramp on my own ticket's age, clamped at both
    /// ends, and a ticket whose `createdAt` hasn't resolved reads as brand new
    /// rather than as infinitely patient.
    func testRelaxationRampsWithMyOwnTicketAge() {
        XCTAssertEqual(MatchRules.relaxation(for: mine, now: now), 0)

        let half = ticket(
            squadId: "mine", members: ["a1"], createdAt: -MatchRules.fullRelaxation / 2
        )
        XCTAssertEqual(MatchRules.relaxation(for: half, now: now), 0.5, accuracy: 0.0001)

        let unresolved = ticket(squadId: "mine", members: ["a1"], createdAt: nil)
        XCTAssertEqual(MatchRules.relaxation(for: unresolved, now: now), 0)

        // A client clock behind the server's must not read as negative age.
        let future = ticket(squadId: "mine", members: ["a1"], createdAt: 600)
        XCTAssertEqual(MatchRules.relaxation(for: future, now: now), 0)
    }

    // MARK: - Court derivation

    /// Preference is the **home** list's order, not distance. Both squads
    /// compute the same answer from the same two lists, which is what makes
    /// negotiating unnecessary.
    func testTheHomeTicketsPreferenceOrderPicksTheCourt() throws {
        let home = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["far", "here"])
        let guest = ticket(
            squadId: "mine", members: ["a1", "a2", "a3"], courtIds: ["here", "far"]
        )

        let match = try XCTUnwrap(candidate(guest, home))

        XCTAssertEqual(
            match.courtId, "far",
            "The home squad's first preference wins even though the guest listed a nearer court first."
        )
    }

    /// A court only the guest listed is never chosen, at any relaxation. The
    /// `seasonGames` create rule checks the *home* ticket's list, so offering
    /// one would turn a legal-looking match into a refused write.
    func testACourtOnlyTheGuestListedIsNeverChosen() throws {
        let home = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["near"])
        let guest = ticket(
            squadId: "mine",
            members: ["a1", "a2", "a3"],
            courtIds: ["here", "near"],
            createdAt: -MatchRules.fullRelaxation
        )

        let match = try XCTUnwrap(candidate(guest, home))

        XCTAssertEqual(match.courtId, "near")
        XCTAssertFalse(home.courtIds.contains("here"))
    }

    /// A court both squads named but this build's dataset doesn't carry is
    /// still a match: they know where they're going even if `courts.json`
    /// doesn't. Only the *relaxed* radius branch needs the dataset.
    func testACourtMissingFromTheDatasetStillMatchesWhenBothNamedIt() throws {
        let home = ticket(squadId: "theirs", members: ["b1", "b2", "b3"], courtIds: ["unknown"])
        let guest = ticket(squadId: "mine", members: ["a1", "a2", "a3"], courtIds: ["unknown"])

        let match = try XCTUnwrap(candidate(guest, home))

        XCTAssertEqual(match.courtId, "unknown")
    }

    // MARK: - Soft-rule ordering

    /// All else equal, the closer record ranks first. This is the
    /// competitive-balance rule and it carries the most weight.
    func testCloserRecordsRankFirst() {
        let even = ticket(squadId: "even", members: ["b1"], wins: 5, losses: 5)
        let slight = ticket(squadId: "slight", members: ["c1"], wins: 6, losses: 4)
        let wide = ticket(squadId: "wide", members: ["d1"], wins: 7, losses: 3)

        let ranked = MatchRules.rank(
            for: mine, against: [wide, slight, even], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(ranked.map(\.ticket.squadId), ["even", "slight", "wide"])
    }

    /// All else equal, the squad that has waited longer is picked first. Pure
    /// fairness, and the reason the pool doesn't starve its earliest arrivals.
    func testTheLongerWaitRanksFirst() {
        let waiting = ticket(
            squadId: "waiting", members: ["b1"], createdAt: -MatchRules.fullRelaxation
        )
        let arrived = ticket(squadId: "arrived", members: ["c1"], createdAt: 0)

        let ranked = MatchRules.rank(
            for: mine, against: [arrived, waiting], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(ranked.map(\.ticket.squadId), ["waiting", "arrived"])
    }

    /// All else equal, the nearer court ranks first.
    func testTheNearerCourtRanksFirst() {
        let closeBy = ticket(squadId: "closeBy", members: ["b1"], courtIds: ["here"])
        let acrossTown = ticket(squadId: "acrossTown", members: ["c1"], courtIds: ["near"])
        let guest = ticket(
            squadId: "mine", members: ["a1", "a2", "a3"], courtIds: ["here", "near"]
        )

        let ranked = MatchRules.rank(
            for: guest, against: [acrossTown, closeBy], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(ranked.map(\.ticket.squadId), ["closeBy", "acrossTown"])
    }

    /// **Three candidates, and the expected one ranks first** — the composite
    /// case, where the weights actually have to trade against each other.
    ///
    /// The arithmetic, since the answer isn't obvious by inspection and that's
    /// the point of pinning it. Travel and overlap are identical for all three
    /// — the court sits on the anchor (0.30 × 1) and the windows give three
    /// hours for a one-hour game (0.15 × 1) — so they contribute a flat 0.45
    /// and the contest is record (0.35) against waiting (0.20):
    ///
    /// - `even`:    gap 0.0, fresh  → 0.45 + 0.35 × 1.00 + 0.20 × 0.00 = 0.800
    /// - `patient`: gap 0.3, waited → 0.45 + 0.35 × 0.70 + 0.20 × 1.00 = 0.895
    /// - `close`:   gap 0.1, fresh  → 0.45 + 0.35 × 0.90 + 0.20 × 0.00 = 0.765
    ///
    /// So a squad that has waited the full relaxation beats a perfectly matched
    /// record — deliberately. A pool that always served the best pairing would
    /// leave its earliest arrivals waiting forever, which is the failure the
    /// fairness weight exists to prevent.
    func testWaitingOutranksAModestRecordGap() {
        let even = ticket(squadId: "even", members: ["b1"], wins: 5, losses: 5, createdAt: 0)
        let patient = ticket(
            squadId: "patient",
            members: ["c1"],
            wins: 8,
            losses: 2,
            createdAt: -MatchRules.fullRelaxation
        )
        let close = ticket(squadId: "close", members: ["d1"], wins: 6, losses: 4, createdAt: 0)

        let ranked = MatchRules.rank(
            for: mine, against: [even, patient, close], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(ranked.map(\.ticket.squadId), ["patient", "even", "close"])
        XCTAssertEqual(ranked[0].score, 0.895, accuracy: 0.0001)
        XCTAssertEqual(ranked[1].score, 0.800, accuracy: 0.0001)
        XCTAssertEqual(ranked[2].score, 0.765, accuracy: 0.0001)
    }

    /// Ties break on squad ID, not on pool order. A Firestore snapshot's order
    /// isn't something to rank on, and without a second key two clients
    /// scanning the same pool could pick different top candidates and claim
    /// past each other.
    func testTiesBreakDeterministicallyOnSquadId() {
        let alpha = ticket(squadId: "alpha", members: ["b1"])
        let bravo = ticket(squadId: "bravo", members: ["c1"])

        let forwards = MatchRules.rank(
            for: mine, against: [alpha, bravo], courts: courts, anchor: anchor, now: now
        )
        let backwards = MatchRules.rank(
            for: mine, against: [bravo, alpha], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(forwards[0].score, forwards[1].score, accuracy: 0.0001)
        XCTAssertEqual(forwards.map(\.ticket.squadId), ["alpha", "bravo"])
        XCTAssertEqual(backwards.map(\.ticket.squadId), ["alpha", "bravo"])
    }

    /// Weights sum to one, so a score is always in `0...1` and two candidates
    /// are comparable by construction. A weight added without adjusting the
    /// others would silently break that.
    func testWeightsSumToOne() {
        let total = MatchRules.Weight.record
            + MatchRules.Weight.travel
            + MatchRules.Weight.waiting
            + MatchRules.Weight.overlap

        XCTAssertEqual(total, 1, accuracy: 0.0001)
    }

    // MARK: - The pool

    func testAnEmptyPoolRanksNothing() {
        XCTAssertTrue(
            MatchRules.rank(for: mine, against: [], courts: courts, anchor: anchor, now: now).isEmpty
        )
    }

    /// My own ticket is in the pool query's results — the query filters on
    /// region and format, not on "not me" — so the scan has to drop it.
    func testMyOwnTicketIsFilteredOutOfThePool() {
        let ranked = MatchRules.rank(
            for: mine, against: [mine, theirs], courts: courts, anchor: anchor, now: now
        )

        XCTAssertEqual(ranked.map(\.ticket.squadId), ["theirs"])
    }

    /// A pool of nothing but incompatible tickets ranks nothing, rather than
    /// falling back to a best-of-a-bad-lot.
    func testAPoolOfIncompatibleTicketsRanksNothing() {
        let pool = [
            ticket(squadId: "sharesPlayer", members: ["a1"]),
            ticket(squadId: "expired", members: ["c1"], expiresAt: -1),
            ticket(squadId: "wrongRegion", members: ["d1"], region: "Cary"),
            ticket(squadId: "matched", members: ["e1"], status: .matched),
        ]

        XCTAssertTrue(
            MatchRules.rank(for: mine, against: pool, courts: courts, anchor: anchor, now: now)
                .isEmpty
        )
    }

    // MARK: - Window arithmetic at the hard boundaries

    private func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0,
        zone: String = "America/New_York"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    /// **A window that spans midnight overlaps correctly with one starting at
    /// 23:30 the same evening.**
    ///
    /// It works because none of this arithmetic knows what a day is: an overlap
    /// is the difference between two instants, and midnight isn't one of them.
    func testAWindowSpanningMidnightOverlapsWithOneStartingAt2330() throws {
        let evening = date(year: 2026, month: 6, day: 10, hour: 22)
        let lateStart = date(year: 2026, month: 6, day: 10, hour: 23, minute: 30)
        let smallHours = date(year: 2026, month: 6, day: 11, hour: 2)
        let oneAM = date(year: 2026, month: 6, day: 11, hour: 1)

        let overnight = calendarTicket(
            squadId: "overnight", members: ["b1", "b2", "b3"], from: evening, to: smallHours
        )
        let lateNight = calendarTicket(
            squadId: "lateNight", members: ["a1", "a2", "a3"], from: lateStart, to: oneAM
        )

        let overlap = try XCTUnwrap(lateNight.overlap(with: overnight))
        XCTAssertEqual(overlap.start, lateStart)
        XCTAssertEqual(overlap.end, oneAM)
        XCTAssertEqual(overlap.duration, 90 * 60, "23:30 to 01:00 is ninety minutes across midnight")

        // An hour before the window opens, so the lead time is never the thing
        // under test here.
        let evaluatedAt = date(year: 2026, month: 6, day: 10, hour: 21)
        let match = try XCTUnwrap(
            MatchRules.candidate(
                for: lateNight, against: overnight, courts: courts, anchor: anchor, now: evaluatedAt
            )
        )

        XCTAssertEqual(match.scheduledTime, lateStart, "Tip-off is the start of the overlap")
        XCTAssertLessThanOrEqual(
            match.scheduledTime.addingTimeInterval(SquadFormat.threeVThree.duration), oneAM
        )
    }

    /// A window spanning the autumn daylight-saving change is an hour longer
    /// than the wall clock says, and the arithmetic has to agree with the
    /// clock on the wall being wrong.
    ///
    /// On 2026-11-01 America/New_York repeats 01:00–02:00, so 00:45 to 03:30
    /// reads as 2h45m on a wall clock and **is** 3h45m. A local-calendar
    /// implementation would compute the former, reject this pair for a window
    /// that's actually plenty long, and give no reason.
    func testAWindowAcrossTheDaylightSavingChangeIsMeasuredInRealTime() throws {
        let start = date(year: 2026, month: 11, day: 1, hour: 0, minute: 45)
        let end = date(year: 2026, month: 11, day: 1, hour: 3, minute: 30)
        let wider = date(year: 2026, month: 11, day: 1, hour: 0, minute: 30)
        let widerEnd = date(year: 2026, month: 11, day: 1, hour: 4)

        XCTAssertEqual(
            end.timeIntervalSince(start), 3.75 * 3_600,
            "00:45 to 03:30 across the fall-back is 3h45m of real time, not the 2h45m a wall clock shows."
        )

        let guest = calendarTicket(
            squadId: "guest", members: ["a1", "a2", "a3"], from: start, to: end
        )
        let home = calendarTicket(
            squadId: "home", members: ["b1", "b2", "b3"], from: wider, to: widerEnd
        )

        let overlap = try XCTUnwrap(guest.overlap(with: home))
        XCTAssertEqual(overlap.duration, 3.75 * 3_600)

        let evaluatedAt = date(year: 2026, month: 10, day: 31, hour: 23)
        let match = try XCTUnwrap(
            MatchRules.candidate(
                for: guest, against: home, courts: courts, anchor: anchor, now: evaluatedAt
            )
        )

        XCTAssertEqual(match.scheduledTime, start)
        XCTAssertEqual(
            match.scheduledTime.timeIntervalSince1970
                .truncatingRemainder(dividingBy: MatchRules.schedulingGrain),
            0,
            accuracy: 0.001
        )
    }

    /// Two clients in different time zones derive the identical instant. The
    /// grain is absolute, so there is nothing for a local calendar to disagree
    /// about.
    func testTheGrainIsAbsoluteNotLocal() {
        let easternHalfPast = date(year: 2026, month: 6, day: 10, hour: 22, minute: 30)
        let kathmandu = date(
            year: 2026, month: 6, day: 11, hour: 8, minute: 15, zone: "Asia/Kathmandu"
        )

        // Kathmandu is UTC+5:45, so the same instant sits at :15 past the hour
        // there and :30 past here. A grain anchored to local midnight would
        // round these two to different instants.
        XCTAssertEqual(easternHalfPast, kathmandu)
        XCTAssertEqual(
            MatchRules.roundedUpToGrain(easternHalfPast),
            MatchRules.roundedUpToGrain(kathmandu)
        )
        XCTAssertEqual(MatchRules.roundedUpToGrain(easternHalfPast), easternHalfPast)
    }

    /// Rounding goes **up**, never down. Rounding down could land inside the
    /// lead-time cushion the rounding was applied after — the sort of
    /// off-by-one that only ever shows up as a rejected write.
    func testTheGrainRoundsUp() {
        let onTheGrain = Date(timeIntervalSince1970: 900)
        let justPast = Date(timeIntervalSince1970: 901)

        XCTAssertEqual(MatchRules.roundedUpToGrain(onTheGrain), onTheGrain)
        XCTAssertEqual(
            MatchRules.roundedUpToGrain(justPast), Date(timeIntervalSince1970: 1_800)
        )
    }

    /// Rounding up can push tip-off past the point where the game still fits,
    /// and that has to be a rejection rather than a game that runs past the
    /// window.
    func testRoundingPastTheFitRejects() {
        let overlap = DateInterval(
            start: Date(timeIntervalSince1970: 100_000_001),
            end: Date(timeIntervalSince1970: 100_000_001 + 3_600 + 60)
        )

        XCTAssertNil(
            MatchRules.scheduledTime(
                in: overlap,
                duration: 3_600,
                now: Date(timeIntervalSince1970: 99_990_000)
            )
        )
    }

    /// A window already open pushes tip-off to the lead-time cushion rather
    /// than to a time in the past.
    func testAnAlreadyOpenWindowSchedulesFromNowPlusLeadTime() throws {
        let overlap = DateInterval(start: now.addingTimeInterval(-3_600), duration: 5 * 3_600)
        let scheduled = try XCTUnwrap(
            MatchRules.scheduledTime(in: overlap, duration: 3_600, now: now)
        )

        XCTAssertGreaterThanOrEqual(scheduled, now.addingTimeInterval(Game.minimumLeadTime))
        XCTAssertLessThan(scheduled, now.addingTimeInterval(Game.minimumLeadTime + MatchRules.schedulingGrain))
    }

    private func calendarTicket(
        squadId: String,
        members: [String],
        from windowStart: Date,
        to windowEnd: Date
    ) -> MatchTicket {
        MatchTicket(
            squadId: squadId,
            leaderId: "\(squadId)_leader",
            squadName: squadId.capitalized,
            memberIds: members,
            format: .threeVThree,
            region: "Durham",
            courtIds: ["here"],
            windowStart: windowStart,
            windowEnd: windowEnd,
            wins: 5,
            losses: 5,
            status: .open,
            claimedBy: nil,
            claimedAt: nil,
            matchedGameId: nil,
            createdAt: windowStart.addingTimeInterval(-3_600),
            expiresAt: windowEnd
        )
    }
}
