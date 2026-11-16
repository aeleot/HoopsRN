import XCTest
@testable import hoopr

/// Guards the 2026-11-14 pre-launch fixes (`PRE_LAUNCH_AUDIT.md` §3.1, §3.4,
/// §3.6 and §5.2) — each a defect a first-week user would have hit, and each
/// decided by a pure function so it can be held here without Firebase.
final class LaunchFixesTests: XCTestCase {

    // MARK: - Signing in (§3.1)

    /// A pasted address often ends in a newline; `.whitespaces` left it on and
    /// Firebase refused the result as an invalid email.
    func testAPastedEmailLosesItsTrailingNewline() {
        XCTAssertEqual(LoginViewModel.normalizedEmail("  jane@example.com\n"), "jane@example.com")
        XCTAssertEqual(LoginViewModel.normalizedEmail("\n\t "), "")
    }

    /// The screen must not say which addresses have accounts: "not found" is
    /// reported with the same sentence a sent link gets, and as a notice, not
    /// an error.
    func testAResetForAnUnknownAddressReadsTheSameAsOneThatWasSent() {
        let outcome = LoginViewModel.passwordResetOutcome(for: AuthError.userNotFound)

        XCTAssertEqual(outcome.notice, LoginViewModel.passwordResetNotice)
        XCTAssertNil(outcome.error)
    }

    func testAResetThatCouldNotBeSentSaysSoAndClaimsNothing() {
        for error in [AuthError.network, .invalidEmail, .tooManyRequests, .userDisabled] {
            let outcome = LoginViewModel.passwordResetOutcome(for: error)

            XCTAssertNil(outcome.notice, "\(error) must not claim a link was sent")
            XCTAssertNotNil(outcome.error)
        }
        XCTAssertEqual(LoginViewModel.passwordResetOutcome(for: AuthError.network).error, FailureText.network)
    }

    // MARK: - Changing accounts (§3.4)

    func testLaunchRestoringASessionClearsNothing() {
        XCTAssertFalse(SessionCleanup.shouldClear(previous: nil, current: "uid-a"))
        XCTAssertFalse(SessionCleanup.shouldClear(previous: nil, current: nil))
        XCTAssertFalse(SessionCleanup.shouldClear(previous: "uid-a", current: "uid-a"))
    }

    func testSigningOutOrSwappingAccountsClears() {
        XCTAssertTrue(SessionCleanup.shouldClear(previous: "uid-a", current: nil))
        XCTAssertTrue(SessionCleanup.shouldClear(previous: "uid-a", current: "uid-b"))
    }

    @MainActor
    func testTheNextAccountDoesNotInheritOnDeviceHistory() throws {
        let suiteName = "LaunchFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recents = RecentCourtsStore(defaults: defaults)
        recents.record(courtId: "court-a")
        InboxDismissalsStore(defaults: defaults).record("card-1")
        CelebratedWinsStore(defaults: defaults).record("game-1")

        recents.clear()
        SessionCleanup.clearDismissalsAndCelebrations(defaults: defaults)

        XCTAssertTrue(recents.recentCourtIds.isEmpty)
        XCTAssertTrue(RecentCourtsStore(defaults: defaults).recentCourtIds.isEmpty)
        XCTAssertTrue(InboxDismissalsStore(defaults: defaults).keys.isEmpty)
        XCTAssertTrue(CelebratedWinsStore(defaults: defaults).keys.isEmpty)
    }

    // MARK: - A new profile's name (§3.6)

    /// The default is never derived from the email, so there is nothing of the
    /// address to leak onto a document every signed-in account can read.
    func testADefaultNameIsValidAndCarriesNoEmail() {
        let name = UserProfileService.defaultUserName(suffix: 4821)

        XCTAssertEqual(name, "Hooper 4821")
        XCTAssertNil(UserProfile.validate(userName: name))
    }

    func testEveryGeneratedDefaultNameFitsTheRule() {
        for _ in 0..<50 {
            let name = UserProfileService.defaultUserName()
            XCTAssertNil(UserProfile.validate(userName: name))
            XCTAssertTrue(name.hasPrefix("Hooper "))
        }
    }

    // MARK: - The last schedulable minute (§5.2)

    /// The rule is a strict `< request.time + 30d` on the server's clock, so
    /// the picker stops short of it rather than offering a minute a fast phone
    /// clock would have refused.
    func testThePickerStopsInsideTheServersWindow() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let range = CreateGameViewModel.scheduleRange(from: now)

        XCTAssertEqual(range.lowerBound, now.addingTimeInterval(Game.minimumLeadTime))
        XCTAssertLessThan(range.upperBound, now.addingTimeInterval(Game.schedulingWindow))
        XCTAssertNil(Game.validate(courtId: "court-a", scheduledTime: range.upperBound, maxPlayers: 10, now: now))
        // Still valid on a phone running half an hour fast.
        XCTAssertNil(
            Game.validate(
                courtId: "court-a",
                scheduledTime: range.upperBound,
                maxPlayers: 10,
                now: now.addingTimeInterval(-30 * 60)
            )
        )
    }
}
