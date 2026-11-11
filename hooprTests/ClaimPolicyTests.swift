import XCTest
@testable import hoopr

/// The claim loop's decisions, which is everything about it that can be wrong
/// in a way nobody notices.
///
/// `MatchmakingService` is a `@MainActor` class holding two Firestore
/// listeners, and no test in this suite instantiates a service. So the loop's
/// judgment — whether a lost race is shown to the user, how many times
/// contention is retried, what a transient failure does — lives in
/// `ClaimPolicy` as pure statics, and this is where it is pinned.
///
/// The other half of the same story is `firestore-tests/claim-race.test.mjs`,
/// which races two real clients against the Firestore emulator. Between them:
/// the *decision* is tested here, the *concurrency guarantee* is tested there,
/// and neither one could be checked by looking at a screen.
final class ClaimPolicyTests: XCTestCase {

    // MARK: - Losing is invisible

    func testLostClaimIsNeverSurfacedToTheUser() {
        XCTAssertFalse(ClaimPolicy.isUserFacing(.lost))
    }

    func testRefusalAndVanishedTicketAreAlsoSilent() {
        XCTAssertFalse(ClaimPolicy.isUserFacing(.refused))
        XCTAssertFalse(ClaimPolicy.isUserFacing(.missing))
        XCTAssertFalse(ClaimPolicy.isUserFacing(.claimed))
    }

    /// The assertion that actually protects the design: a new outcome added
    /// later can't quietly become user-facing without this failing.
    func testOnlyATransactionFailureReachesABanner() {
        XCTAssertTrue(ClaimPolicy.isUserFacing(.failed))

        let surfaced = ClaimOutcome.allCases.filter(ClaimPolicy.isUserFacing)
        XCTAssertEqual(
            surfaced,
            [.failed],
            "Only .failed may reach a banner — losing a race is invisible by design. Got \(surfaced)."
        )
    }

    // MARK: - What happens next

    func testWonClaimStopsTheSearch() {
        XCTAssertEqual(ClaimPolicy.next(after: .claimed, attempt: 1), .stop)
        XCTAssertEqual(ClaimPolicy.next(after: .claimed, attempt: 3), .stop)
        XCTAssertTrue(ClaimPolicy.isTerminal(.claimed))
    }

    func testLostClaimRescansWhileAttemptsRemain() {
        XCTAssertEqual(ClaimPolicy.next(after: .lost, attempt: 1), .rescan)
        XCTAssertEqual(ClaimPolicy.next(after: .lost, attempt: 2), .rescan)
    }

    func testThirdLostClaimBacksOffToTheQuietPoll() {
        XCTAssertEqual(
            ClaimPolicy.next(after: .lost, attempt: ClaimPolicy.maximumAttempts),
            .backOff(ClaimPolicy.backOffInterval)
        )
    }

    func testRefusalAndMissingTicketFollowTheSamePathAsALoss() {
        for outcome in [ClaimOutcome.refused, .missing] {
            XCTAssertEqual(
                ClaimPolicy.next(after: outcome, attempt: 1),
                .rescan,
                "\(outcome.rawValue) should re-scan on its first attempt"
            )
            XCTAssertEqual(
                ClaimPolicy.next(after: outcome, attempt: ClaimPolicy.maximumAttempts),
                .backOff(ClaimPolicy.backOffInterval),
                "\(outcome.rawValue) should back off once attempts are spent"
            )
        }
    }

    /// A transaction that never reached the server says nothing about the pool,
    /// so re-ranking would burn another attempt on the same stale answer.
    func testTransactionFailureBacksOffImmediately() {
        XCTAssertEqual(
            ClaimPolicy.next(after: .failed, attempt: 1),
            .backOff(ClaimPolicy.backOffInterval)
        )
    }

    func testAttemptCountPastTheCeilingStillBacksOff() {
        XCTAssertEqual(
            ClaimPolicy.next(after: .lost, attempt: ClaimPolicy.maximumAttempts + 5),
            .backOff(ClaimPolicy.backOffInterval)
        )
    }

    // MARK: - Tuning

    func testBackOffMatchesThePlan() {
        XCTAssertEqual(ClaimPolicy.backOffInterval, 15, "the design specifies a 15-second poll")
        XCTAssertEqual(ClaimPolicy.maximumAttempts, 3, "the design caps at three attempts")
    }

    func testJitterAlwaysLandsInsideItsRange() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let delay = ClaimPolicy.jitterDelay(using: &generator)
            XCTAssertTrue(
                ClaimPolicy.jitter.contains(delay),
                "jitter produced \(delay), outside \(ClaimPolicy.jitter)"
            )
        }
    }

    /// A jitter that returned a constant would spread nothing and would still
    /// pass a bounds check, which is the failure worth catching.
    func testJitterSpansItsRangeRatherThanCollapsing() {
        var generator = SystemRandomNumberGenerator()
        let samples = (0..<200).map { _ in ClaimPolicy.jitterDelay(using: &generator) }

        XCTAssertGreaterThan(Set(samples).count, 1)
        XCTAssertLessThan(samples.min() ?? .infinity, 1.5)
        XCTAssertGreaterThan(samples.max() ?? 0, 2.0)
    }

    func testJitterFloorIsNonZero() {
        // A zero floor would let every client claim in the same instant, which
        // is the thundering herd the jitter exists for.
        XCTAssertGreaterThan(ClaimPolicy.jitter.lowerBound, 0)
        XCTAssertEqual(ClaimPolicy.jitter, 0.5...3.0)
    }
}
