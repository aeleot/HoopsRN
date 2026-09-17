import XCTest
@testable import hoopr

/// Covers the decision the matchmaking card makes that isn't a matter of
/// layout: **which state to show**.
///
/// `MatchmakingViewModel.phase` is `nonisolated static` precisely so it can be
/// exercised here — it needs no Firebase, no main actor and no live service,
/// and it is the part most likely to break silently. Its failure mode isn't a
/// crash: it is a search spinner, with a climbing timer, for a search that is
/// not running.
///
/// **The bug these pin.** `phase` used to read *any* non-nil ticket as
/// `.searching`. Nothing deletes a ticket once it is spent on a match — it
/// sits there `matched` until `expiresAt`, up to a day later. So the moment the
/// match stopped being live, whether it had been played and confirmed, called
/// off, or simply aged past its window, the card fell back to a search nobody
/// had started, counting up from when the squad first queued. The only control
/// on it was "Cancel search", which cancelled nothing, because there was
/// nothing running to cancel.
///
/// **The hole the fix left.** Reading a spent ticket correctly needed a third
/// state — `.settling`, for the moment between a match being committed and it
/// arriving on this client's `seasonGames` listener. Nothing re-evaluates
/// `phase` once the ticket itself stops changing, so if `committedGame` never
/// resolves — a `matchedGameId` pointing at a document this client can't see —
/// `.settling` had no way out either: a permanent spinner. `settlingGrace`
/// bounds that wait and falls back to `.idle`, and the "settling grace period"
/// section below is what pins it.
final class MatchmakingViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    // MARK: - Fixtures

    private func ticket(
        _ status: MatchTicket.Status,
        matchedGameId: String? = nil
    ) -> MatchTicket {
        MatchTicket(
            squadId: "squad-mine",
            leaderId: "leader-mine",
            squadName: "Rim Reapers",
            memberIds: ["leader-mine"],
            format: .threeVThree,
            region: "Durham",
            courtIds: ["court-1"],
            windowStart: now.addingTimeInterval(3_600),
            windowEnd: now.addingTimeInterval(18_000),
            wins: 0,
            losses: 0,
            status: status,
            claimedBy: status == .matched ? "squad-theirs" : nil,
            claimedAt: status == .matched ? now : nil,
            matchedGameId: matchedGameId,
            createdAt: now.addingTimeInterval(-600),
            expiresAt: now.addingTimeInterval(7_200)
        )
    }

    private func game(id: String = "game-1", status: SeasonGame.Status = .scheduled) -> SeasonGame {
        SeasonGame(
            id: id,
            format: .threeVThree,
            region: "Durham",
            homeSquadId: "squad-theirs",
            awaySquadId: "squad-mine",
            squadIds: ["squad-theirs", "squad-mine"],
            homeLeaderId: "leader-theirs",
            awayLeaderId: "leader-mine",
            homeSquadName: "Court Vision",
            awaySquadName: "Rim Reapers",
            courtId: "court-1",
            scheduledTime: now.addingTimeInterval(3_600),
            status: status,
            arrivedPlayerIds: [],
            homeReport: nil,
            awayReport: nil,
            homeScore: nil,
            awayScore: nil,
            result: nil,
            cancelledBySquadId: nil,
            createdBy: "leader-mine",
            createdAt: now,
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    private func phase(
        ticket: MatchTicket?,
        nextGame: SeasonGame? = nil,
        committedGame: SeasonGame? = nil,
        hasSettlingTimedOut: Bool = false
    ) -> MatchmakingViewModel.Phase {
        MatchmakingViewModel.phase(
            ticket: ticket,
            nextGame: nextGame,
            committedGame: committedGame,
            hasSettlingTimedOut: hasSettlingTimedOut
        )
    }

    // MARK: - The ordinary path

    func testNoTicketIsIdle() {
        XCTAssertEqual(phase(ticket: nil), .idle)
    }

    func testAnOpenTicketIsSearching() {
        XCTAssertEqual(phase(ticket: ticket(.open)), .searching)
    }

    func testALiveMatchIsShownWhateverTheTicketSays() {
        let live = game()

        XCTAssertEqual(phase(ticket: ticket(.matched, matchedGameId: "game-1"), nextGame: live), .matched(live))
        // Including the case where the ticket has already aged out from under
        // the match — the match is the thing the squad actually has on.
        XCTAssertEqual(phase(ticket: nil, nextGame: live), .matched(live))
    }

    // MARK: - The spent ticket

    /// **The reported bug.** Both leaders reported a result, the match is
    /// `confirmed`, so it is correctly no longer a *live* match — and the ticket
    /// is still sitting there spent, as it will be for hours. That combination
    /// is a squad with nothing on, not a squad searching.
    func testASpentTicketWhoseMatchIsConfirmedIsIdle() {
        let confirmed = game(status: .confirmed)

        XCTAssertEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), nextGame: nil, committedGame: confirmed),
            .idle
        )
    }

    /// The same shape from the other reported direction: the match was called
    /// off. The card used to show the searching state here too, with a timer
    /// that only stopped if the leader tapped "Cancel search".
    func testASpentTicketWhoseMatchWasCancelledIsIdle() {
        let cancelled = game(status: .cancelled)

        XCTAssertEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), nextGame: nil, committedGame: cancelled),
            .idle
        )
    }

    /// And the third way a match stops being live without anything being
    /// written: it simply aged past its window.
    func testASpentTicketWhoseMatchAgedOutIsIdle() {
        let old = game(status: .scheduled)

        XCTAssertEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), nextGame: nil, committedGame: old),
            .idle
        )
    }

    /// The one case a spent ticket legitimately isn't idle: the commit landed
    /// and the match hasn't reached this client yet. Both are written in one
    /// transaction, but they arrive on two listeners, and the ticket's usually
    /// wins by a few hundred milliseconds.
    func testASpentTicketWhoseMatchHasNotArrivedIsSettling() {
        XCTAssertEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), nextGame: nil, committedGame: nil),
            .settling
        )
    }

    /// A spent ticket that names no match at all can only be read as settling
    /// too — it is never a search, which is the property that matters. In
    /// practice the rules make this unreachable: `matchedGameId` is required by
    /// both halves of the commit, so a ticket cannot reach `matched` without
    /// one.
    func testASpentTicketWithNoMatchNamedIsNeverSearching() {
        XCTAssertNotEqual(phase(ticket: ticket(.matched)), .searching)
    }

    // MARK: - The settling grace period

    /// **The hole in the fix above.** Nothing re-evaluates `phase` once the
    /// ticket stops changing, so a `committedGame` that never arrives — a
    /// `matchedGameId` pointing at a document this client can't see, whether
    /// from a hand-edited ticket or some other corruption — left `.settling`
    /// with no way out at all: a permanent spinner, worse than the bug it
    /// replaced, because "Cancel search" wasn't even shown for it to fail to
    /// work.
    func testASettledTimeoutFallsBackToIdle() {
        XCTAssertEqual(
            phase(
                ticket: ticket(.matched, matchedGameId: "game-1"),
                nextGame: nil,
                committedGame: nil,
                hasSettlingTimedOut: true
            ),
            .idle
        )
    }

    /// The timeout only ever matters while `committedGame` is still nil. Once
    /// the match has actually arrived, a stale `hasSettlingTimedOut: true` left
    /// over from a *previous* wait must not un-resolve it back to idle —
    /// `committedGame`'s presence wins.
    func testAResolvedMatchIsIdleRegardlessOfAStaleTimeoutFlag() {
        let confirmed = game(status: .confirmed)

        XCTAssertEqual(
            phase(
                ticket: ticket(.matched, matchedGameId: "game-1"),
                nextGame: nil,
                committedGame: confirmed,
                hasSettlingTimedOut: true
            ),
            .idle
        )
    }

    // MARK: - Queueing again

    /// One live match at a time, expressed where the button reads it. `canQueue`
    /// is `isLeader && phase == .idle`, so these are the phases that must not
    /// offer a leader the queue: a live match, a running search, and the moment
    /// between the commit and the card.
    func testOnlyIdleOffersTheQueue() {
        let live = game()

        XCTAssertEqual(phase(ticket: nil), .idle)
        XCTAssertNotEqual(phase(ticket: ticket(.open)), .idle)
        XCTAssertNotEqual(phase(ticket: ticket(.matched, matchedGameId: "game-1")), .idle)
        XCTAssertNotEqual(phase(ticket: nil, nextGame: live), .idle)
        // Still settling, still not idle — a leader must not be offered the
        // queue while a commit might still land as a match.
        XCTAssertNotEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), hasSettlingTimedOut: false),
            .idle
        )
    }

    /// The other side of the same button: once the wait has genuinely timed
    /// out, `canQueue` must unlock. That's the entire reason the timeout
    /// exists — a leader stuck behind a match that will never arrive has to be
    /// able to try again.
    func testATimedOutSettleUnlocksTheQueue() {
        XCTAssertEqual(
            phase(ticket: ticket(.matched, matchedGameId: "game-1"), hasSettlingTimedOut: true),
            .idle
        )
    }
}
