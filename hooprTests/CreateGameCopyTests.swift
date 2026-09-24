import XCTest
@testable import hoopr

/// What the "Start a Run" sheet says about invite-only runs, and what it hands
/// a host to send.
///
/// **The rule these pin** (`gaps/GAMES.md`): the invite link opens
/// nothing and the `games` read rule refuses a non-member, so an invite-only
/// run holds only its host. The sheet must not promise otherwise — it did,
/// twice ("You'll get a link to share with the players you want in", and "send
/// this link to the players you want in").
@MainActor
final class CreateGameCopyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Visibility

    func testThePublicCaptionSaysWhoCanJoin() {
        XCTAssertEqual(
            CreateGameViewModel.visibilityCaption(isPublic: true),
            "Anyone nearby can find and join."
        )
    }

    /// Invite-only says what it does today — hidden, and the host alone until
    /// invites work — and never offers the link as the way in. Shortened to
    /// one line on 2026-09-23 without losing either half.
    func testTheInviteOnlyCaptionDoesNotPromiseAWorkingInvite() {
        let caption = CreateGameViewModel.visibilityCaption(isPublic: false)

        XCTAssertTrue(caption.hasPrefix("Hidden."), caption)
        XCTAssertTrue(caption.contains("Just you until invites work"), caption)
        XCTAssertFalse(caption.lowercased().contains("link to share"), caption)
    }

    /// Both captions stay one short line under their option.
    func testTheCaptionsAreShort() {
        for isPublic in [true, false] {
            XCTAssertLessThanOrEqual(CreateGameViewModel.visibilityCaption(isPublic: isPublic).count, 40)
        }
    }

    // MARK: - What the host sends

    func testTheShareTextNamesTheCourtCityAndTime() {
        XCTAssertEqual(
            CreateGameViewModel.shareText(courtName: "East End Park", city: "Durham", day: "Tonight", time: "7:30 PM"),
            "Pickup run at East End Park, Durham — Tonight at 7:30 PM"
        )
    }

    /// A court with no city doesn't leave a dangling comma.
    func testTheShareTextWithoutACity() {
        XCTAssertEqual(
            CreateGameViewModel.shareText(courtName: "East End Park", city: "", day: "Tomorrow", time: "6:00 PM"),
            "Pickup run at East End Park — Tomorrow at 6:00 PM"
        )
    }

    // MARK: - The pick reads as the run will

    /// The sheet's day label and a run's are the same function, so a pick of
    /// "Tonight" is still "Tonight" once the run exists.
    func testThePicksDayTextMatchesARunsSplit() {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: morning)!
        let lunch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: evening)!
        let nextWeek = calendar.date(byAdding: .day, value: 6, to: evening)!

        XCTAssertEqual(Game.dayText(for: evening, relativeTo: morning), "Tonight")
        XCTAssertEqual(Game.dayText(for: lunch, relativeTo: morning), "Today")
        XCTAssertEqual(Game.dayText(for: tomorrow, relativeTo: morning), "Tomorrow")
        XCTAssertFalse(["Tonight", "Today", "Tomorrow"].contains(Game.dayText(for: nextWeek, relativeTo: morning)))
    }
}
