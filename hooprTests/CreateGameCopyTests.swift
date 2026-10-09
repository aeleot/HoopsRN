import XCTest
@testable import hoopr

/// What the "Start a Run" sheet says about invite-only runs, and what it hands
/// a host to send.
///
/// **The rule these pin**: the sheet says what an invite-only run actually
/// does. Until 2026-10-08 that meant refusing to promise a working link — it
/// opened nothing, and the sheet had promised it twice. Now the link opens the
/// run and anyone holding it can join, so the caption says exactly that, and
/// what the host sends carries the link along with the court and time.
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

    /// Invite-only says both halves of what it does: hidden from the board,
    /// and open to anyone holding the link — which is the authorization model
    /// (`database/DATABASE_SCHEMA.md`), so a host choosing it should read it.
    func testTheInviteOnlyCaptionSaysTheLinkLetsAnyoneIn() {
        let caption = CreateGameViewModel.visibilityCaption(isPublic: false)

        XCTAssertTrue(caption.hasPrefix("Hidden."), caption)
        XCTAssertTrue(caption.contains("Anyone with the link"), caption)
        XCTAssertFalse(caption.contains("until invites work"), caption)
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

    /// The link rides along on its own line, after the sentence everyone can
    /// act on — a recipient without the app still learns where and when.
    func testTheShareTextCarriesTheLinkAfterTheCourtAndTime() {
        XCTAssertEqual(
            CreateGameViewModel.shareText(
                courtName: "East End Park",
                city: "Durham",
                day: "Tonight",
                time: "7:30 PM",
                link: "hoopsrn://game/abc123"
            ),
            "Pickup run at East End Park, Durham — Tonight at 7:30 PM\nhoopsrn://game/abc123"
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
