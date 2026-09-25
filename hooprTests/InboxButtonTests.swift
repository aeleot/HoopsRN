import XCTest
@testable import hoopr

/// The inbox button's badge rule — the one part of the button worth having in
/// one place, and the part the profile's old tray got wrong: it counted friend
/// requests only, so a squad invite on its own lit the corner dot and left the
/// tray it led to unbadged.
final class InboxButtonTests: XCTestCase {

    // MARK: - What counts as waiting

    func testNothingWaitingIsZero() {
        XCTAssertEqual(InboxButton.waitingCount(incomingRequests: 0, incomingInvites: 0), 0)
    }

    /// A squad invite on its own still badges the tray.
    func testASquadInviteAloneCounts() {
        XCTAssertEqual(InboxButton.waitingCount(incomingRequests: 0, incomingInvites: 1), 1)
    }

    func testRequestsAndInvitesAreSummed() {
        XCTAssertEqual(InboxButton.waitingCount(incomingRequests: 2, incomingInvites: 3), 5)
    }

    // MARK: - How the count is drawn

    func testSingleDigitsAreDrawnAsIs() {
        XCTAssertEqual(InboxButton.badgeText(for: 1), "1")
        XCTAssertEqual(InboxButton.badgeText(for: 9), "9")
    }

    /// Two glyphs at most, so the badge fits at every Dynamic Type size.
    func testDoubleDigitsCapAtNinePlus() {
        XCTAssertEqual(InboxButton.badgeText(for: 10), "9+")
        XCTAssertEqual(InboxButton.badgeText(for: 42), "9+")
    }
}
