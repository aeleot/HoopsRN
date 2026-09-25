import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `MatchTicket` and the documents stored in
/// `matchTickets`, and covers the pure helpers `MatchRules` is built on.
///
/// The decoding half runs through `Firestore.Decoder` — the same decoder the
/// pool listener will use — so a field rename breaks a test here rather than
/// silently emptying the pool, which is a failure that looks exactly like
/// "nobody else is queued".
final class MatchTicketTests: XCTestCase {

    private let decoder = Firestore.Decoder()
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - Fixtures

    private func document(
        overrides: [String: Any] = [:],
        removing keys: [String] = []
    ) -> [String: Any] {
        var document: [String: Any] = [
            "squadId": "sq_1",
            "leaderId": "leader_1",
            "squadName": "Rim Reapers",
            "memberIds": ["leader_1", "member_2", "member_3"],
            "format": "3v3",
            "region": "Durham",
            "courtIds": ["court_a", "court_b"],
            "windowStart": Timestamp(date: now.addingTimeInterval(3_600)),
            "windowEnd": Timestamp(date: now.addingTimeInterval(4 * 3_600)),
            "wins": 3,
            "losses": 1,
            "status": "open",
            "createdAt": Timestamp(date: now),
            "expiresAt": Timestamp(date: now.addingTimeInterval(2 * 3_600)),
        ]
        for key in keys { document.removeValue(forKey: key) }
        for (key, value) in overrides { document[key] = value }
        return document
    }

    // MARK: - Decoding

    func testDecodesStoredDocumentShape() throws {
        let ticket = try decoder.decode(MatchTicket.self, from: document())

        XCTAssertEqual(ticket.squadId, "sq_1")
        XCTAssertEqual(ticket.id, "sq_1", "The document ID is the squad ID")
        XCTAssertEqual(ticket.leaderId, "leader_1")
        XCTAssertEqual(ticket.squadName, "Rim Reapers")
        XCTAssertEqual(ticket.memberIds, ["leader_1", "member_2", "member_3"])
        XCTAssertEqual(ticket.format, .threeVThree)
        XCTAssertEqual(ticket.region, "Durham")
        XCTAssertEqual(ticket.courtIds, ["court_a", "court_b"])
        XCTAssertEqual(ticket.wins, 3)
        XCTAssertEqual(ticket.losses, 1)
        XCTAssertEqual(ticket.status, .open)
        XCTAssertNil(ticket.claimedBy)
        XCTAssertNil(ticket.claimedAt)
        XCTAssertNil(ticket.matchedGameId)
    }

    /// The spent shape — the home ticket's, which carries all three. The away
    /// squad spends its own, so nobody claimed it and `claimedBy` stays absent
    /// there; both carry the same `matchedGameId`, written in the same commit
    /// as the match, which is the back-reference tying one match to both
    /// squads.
    func testDecodesASpentTicket() throws {
        let claimedAt = Timestamp(date: now.addingTimeInterval(-30))
        let ticket = try decoder.decode(
            MatchTicket.self,
            from: document(overrides: [
                "status": "matched",
                "claimedBy": "sq_2",
                "claimedAt": claimedAt,
                "matchedGameId": "game_1",
            ])
        )

        XCTAssertEqual(ticket.status, .matched)
        XCTAssertEqual(ticket.claimedBy, "sq_2")
        XCTAssertEqual(ticket.claimedAt, claimedAt.dateValue())
        XCTAssertEqual(ticket.matchedGameId, "game_1")
    }

    /// **A ticket the old two-step design wrote must not decode.**
    ///
    /// `claimed` named the gap between claiming a ticket and writing the match
    /// — a gap two clients could disagree about, and the reason two squads that
    /// picked each other both committed. A match is one transaction now, so the
    /// state has no meaning; a leftover document carrying it is skipped by the
    /// per-document decoding rather than being read as something live.
    func testAClaimedTicketNoLongerDecodes() {
        XCTAssertThrowsError(
            try decoder.decode(
                MatchTicket.self,
                from: document(overrides: ["status": "claimed", "claimedBy": "sq_2"])
            )
        )
    }

    /// **`memberIds` is what the no-shared-players rule reads**, so a document
    /// without it has to fail rather than decode as an empty roster — an empty
    /// roster is disjoint from everything, which would make the single most
    /// important hard rule silently pass for every pair.
    func testMissingMemberIdsFailsToDecode() {
        XCTAssertThrowsError(
            try decoder.decode(MatchTicket.self, from: document(removing: ["memberIds"]))
        )
    }

    func testEveryRequiredFieldIsRequired() {
        let required = [
            "squadId", "leaderId", "squadName", "format", "region",
            "courtIds", "windowStart", "windowEnd", "wins", "losses",
            "status", "expiresAt",
        ]

        for key in required {
            XCTAssertThrowsError(
                try decoder.decode(MatchTicket.self, from: document(removing: [key])),
                "A ticket without `\(key)` decoded anyway — it should have failed."
            )
        }
    }

    /// `createdAt` is the one that may be absent: a server timestamp reads back
    /// as null on the writer's own snapshot, before the server resolves it.
    func testDecodesAPendingCreatedAt() throws {
        let ticket = try decoder.decode(
            MatchTicket.self, from: document(overrides: ["createdAt": NSNull()])
        )

        XCTAssertNil(ticket.createdAt)
        XCTAssertEqual(
            MatchRules.relaxation(for: ticket, now: now), 0,
            "A ticket whose createdAt hasn't resolved is brand new, not infinitely patient."
        )
    }

    func testDecodesOnlyTheDeclaredStatuses() {
        XCTAssertThrowsError(
            try decoder.decode(MatchTicket.self, from: document(overrides: ["status": "cancelled"]))
        )
    }

    // MARK: - Claimability

    private func ticket(
        status: MatchTicket.Status,
        claimedAt: TimeInterval?
    ) -> MatchTicket {
        var overrides: [String: Any] = ["status": status.rawValue]
        if let claimedAt {
            overrides["claimedAt"] = Timestamp(date: now.addingTimeInterval(claimedAt))
            overrides["claimedBy"] = "sq_other"
        }
        return try! decoder.decode(MatchTicket.self, from: document(overrides: overrides))
    }

    func testOpenTicketsAreClaimable() {
        XCTAssertTrue(ticket(status: .open, claimedAt: nil).isClaimable(at: now))
    }

    func testMatchedTicketsAreNeverClaimable() {
        XCTAssertFalse(ticket(status: .matched, claimedAt: nil).isClaimable(at: now))
        XCTAssertFalse(ticket(status: .matched, claimedAt: -10_000).isClaimable(at: now))
    }

    /// **Spending is terminal, at any age.** The ninety-second stale-claim
    /// recovery this test used to pin is gone with the state it recovered: a
    /// match is one transaction, so no ticket is ever spoken for without being
    /// spent, and nothing has to time out. A spent ticket that is hours old is
    /// as unclaimable as one spent a second ago.
    func testSpendingATicketIsTerminalAtAnyAge() {
        XCTAssertFalse(ticket(status: .matched, claimedAt: -1).isClaimable(at: now))
        XCTAssertFalse(ticket(status: .matched, claimedAt: -91).isClaimable(at: now))
        XCTAssertFalse(ticket(status: .matched, claimedAt: -86_400).isClaimable(at: now))
    }

    /// **A spent ticket is not a search**, however long it lingers.
    ///
    /// Nothing deletes a ticket once it is spent — it ages out on `expiresAt`,
    /// up to a day later. Reading one as a live search is what left a squad
    /// looking at a spinner and a climbing timer after their match had already
    /// been played and confirmed.
    func testOnlyAnOpenTicketReadsAsSearching() {
        XCTAssertTrue(ticket(status: .open, claimedAt: nil).isSearching)
        XCTAssertFalse(ticket(status: .matched, claimedAt: -1).isSearching)
        XCTAssertFalse(ticket(status: .matched, claimedAt: -86_400).isSearching)
    }

    // MARK: - Records

    /// How a record *compares* is `MatchRules.recordRating`'s, and tested in
    /// `MatchRulesTests`. What stays here is decoding the counts.
    func testARecordDecodesAsPlayed() throws {
        let ticket = try decoder.decode(
            MatchTicket.self, from: document(overrides: ["wins": 3, "losses": 1])
        )

        XCTAssertEqual(ticket.wins, 3)
        XCTAssertEqual(ticket.losses, 1)
        XCTAssertFalse(ticket.isUnplayed)
    }

    func testANoGameRecordIsUnplayed() throws {
        let ticket = try decoder.decode(
            MatchTicket.self, from: document(overrides: ["wins": 0, "losses": 0])
        )

        XCTAssertTrue(ticket.isUnplayed)
    }

    // MARK: - Validation

    private func validate(
        courtIds: [String] = ["court_a"],
        windowStart: TimeInterval = 3_600,
        windowEnd: TimeInterval = 4 * 3_600,
        expiresAt: TimeInterval = 2 * 3_600
    ) -> MatchTicketError? {
        MatchTicket.validate(
            courtIds: courtIds,
            windowStart: now.addingTimeInterval(windowStart),
            windowEnd: now.addingTimeInterval(windowEnd),
            expiresAt: now.addingTimeInterval(expiresAt),
            format: .threeVThree,
            now: now
        )
    }

    func testAWellFormedTicketValidates() {
        XCTAssertNil(validate())
    }

    func testCourtSelectionBoundsAreEnforced() {
        let tooMany = (0...MatchTicket.courtCountRange.upperBound).map { "court_\($0)" }

        XCTAssertEqual(validate(courtIds: []), .invalidCourtSelection)
        XCTAssertEqual(validate(courtIds: tooMany), .invalidCourtSelection)
        XCTAssertNil(validate(courtIds: ["court_a"]))
        XCTAssertNil(
            validate(courtIds: (0..<MatchTicket.courtCountRange.upperBound).map { "court_\($0)" })
        )
    }

    /// A preference order can't rank a court against itself, and a duplicate
    /// would also skew the intersection the match rules compute.
    func testDuplicateCourtsAreRejected() {
        XCTAssertEqual(validate(courtIds: ["court_a", "court_a"]), .duplicateCourts)
    }

    func testWindowMustBeOrderedAndLongEnough() {
        XCTAssertEqual(validate(windowStart: 4 * 3_600, windowEnd: 3_600), .invalidWindow)
        XCTAssertEqual(validate(windowStart: 3_600, windowEnd: 3_600), .invalidWindow)
        XCTAssertEqual(
            validate(windowStart: 3_600, windowEnd: 3_600 + 1_800), .windowTooShort,
            "Half an hour can't hold a sixty-minute game."
        )
    }

    func testAWindowAlreadyPastIsRejected() {
        XCTAssertEqual(
            validate(windowStart: -4 * 3_600, windowEnd: -3_600), .windowInThePast
        )
    }

    /// The same ceiling `Game.schedulingWindow` puts on a pickup run, reused so
    /// the two can't disagree about how far ahead the app plans.
    func testAWindowBeyondTheSchedulingCeilingIsRejected() {
        let beyond = Game.schedulingWindow + 3_600

        XCTAssertEqual(
            validate(windowStart: beyond, windowEnd: beyond + 4 * 3_600, expiresAt: 3_600),
            .windowTooFar
        )
    }

    func testTicketLifetimeBoundsAreEnforced() {
        XCTAssertEqual(
            validate(expiresAt: MatchTicket.lifetimeRange.lowerBound - 60), .expiryTooSoon
        )
        XCTAssertEqual(
            validate(expiresAt: MatchTicket.lifetimeRange.upperBound + 60), .expiryTooFar
        )
        XCTAssertNil(validate(expiresAt: MatchTicket.lifetimeRange.lowerBound))
        XCTAssertNil(
            validate(
                windowStart: 3_600,
                windowEnd: 4 * 3_600,
                expiresAt: MatchTicket.lifetimeRange.upperBound
            )
        )
    }

    // MARK: - Overlap

    func testOverlapIsTheIntersectionOfTwoWindows() throws {
        let a = try decoder.decode(MatchTicket.self, from: document())
        let b = try decoder.decode(
            MatchTicket.self,
            from: document(overrides: [
                "squadId": "sq_2",
                "windowStart": Timestamp(date: now.addingTimeInterval(2 * 3_600)),
                "windowEnd": Timestamp(date: now.addingTimeInterval(6 * 3_600)),
            ])
        )

        let overlap = try XCTUnwrap(a.overlap(with: b))
        XCTAssertEqual(overlap.start, now.addingTimeInterval(2 * 3_600))
        XCTAssertEqual(overlap.end, now.addingTimeInterval(4 * 3_600))

        // Symmetric — which side asks can't change the answer.
        XCTAssertEqual(b.overlap(with: a), overlap)
    }

    func testSharesPlayerIsSymmetricAndExact() throws {
        let a = try decoder.decode(MatchTicket.self, from: document())
        let overlapping = try decoder.decode(
            MatchTicket.self,
            from: document(overrides: ["squadId": "sq_2", "memberIds": ["x", "member_2"]])
        )
        let disjoint = try decoder.decode(
            MatchTicket.self,
            from: document(overrides: ["squadId": "sq_3", "memberIds": ["x", "y"]])
        )

        XCTAssertTrue(a.sharesPlayer(with: overlapping))
        XCTAssertTrue(overlapping.sharesPlayer(with: a))
        XCTAssertFalse(a.sharesPlayer(with: disjoint))
        XCTAssertFalse(disjoint.sharesPlayer(with: a))
    }
}
