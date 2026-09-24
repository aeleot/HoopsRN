import SwiftUI
import XCTest
@testable import hoopr

/// UI revamp Phase 6: the rules the consolidated components carry, which each
/// used to be copied at every call site — and so could differ between them.
/// Their colours are held in `ThemeContrastTests`
/// (`testEveryRunStatusBadgeReadsOnEveryGround`,
/// `testEveryButtonRoleReadsOnItsFill`).
@MainActor
final class ComponentConsolidationTests: XCTestCase {

    // MARK: - A run's status

    /// **Your own relationship to the run says more than its status.** Home,
    /// the Runs card and the map's card each carried this ladder, and Home's
    /// said in a comment that it was copying `GameCard`'s by hand.
    func testHostingBeatsTheWaitlistWhichBeatsFull() {
        XCTAssertEqual(RunStatus.of(isHost: true, isWaitlisted: true, isFull: true), .hosting)
        XCTAssertEqual(RunStatus.of(isHost: false, isWaitlisted: true, isFull: true), .waitlisted)
        XCTAssertEqual(RunStatus.of(isHost: false, isWaitlisted: false, isFull: true), .full)
    }

    func testARunWithNothingToFlagHasNoBadge() {
        XCTAssertNil(RunStatus.of(isHost: false, isWaitlisted: false, isFull: false))
    }

    /// The words are the ones the screens always showed — `badge` type
    /// uppercases them for display, and VoiceOver reads them as words.
    func testStatusesKeepTheirWords() {
        XCTAssertEqual(RunStatus.allCases.map(\.text), ["Hosting", "Waitlist", "Full"])
    }

    /// Home's band gets the lighter wash, for the measured reason in
    /// `HooprBadge.Ground`; a card gets the stronger one.
    func testABandTakesALighterWashThanACard() {
        XCTAssertLessThan(HooprBadge.Ground.band.washOpacity, HooprBadge.Ground.surface.washOpacity)
    }

    // MARK: - The filled button

    /// Every size keeps the 44pt floor a thumb needs, whatever it draws.
    func testEverySizeHasAFullTapTarget() {
        for size in HooprButtonStyle.Size.allCases {
            XCTAssertGreaterThanOrEqual(size.tapTarget, 44, "\(size)")
            XCTAssertGreaterThanOrEqual(size.tapTarget, size.height, "\(size)")
        }
    }

    /// Three sizes that stay three — the audit's complaint was six heights
    /// nobody chose.
    func testTheSizesAreDistinctAndOrdered() {
        let heights = HooprButtonStyle.Size.allCases.map(\.height)
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, heights.count)
        XCTAssertEqual(HooprButtonStyle.Size.large.height, HooprField.minimumHeight,
                       "a form's submit is as tall as the fields above it")
    }

    /// A screen's main action spans its container; a lone action or one in a
    /// row hugs its label unless the caller says otherwise.
    func testOnlyALargeButtonFillsTheWidthByDefault() {
        XCTAssertTrue(HooprButtonStyle(.large).fillsWidth)
        XCTAssertFalse(HooprButtonStyle(.regular).fillsWidth)
        XCTAssertFalse(HooprButtonStyle(.compact).fillsWidth)
        XCTAssertTrue(HooprButtonStyle(.compact, fillsWidth: true).fillsWidth)
    }

    /// A leave or a cancel is not an error, so red is its label, never a fill
    /// that would read as a warning.
    func testOnlyThePrimaryRoleIsFilledOrange() {
        for role in HooprButtonStyle.Role.allCases {
            XCTAssertEqual(role.background == .hooprOrange, role == .primary, "\(role)")
        }
    }

    // MARK: - Avatars

    /// Named sizes stay distinct and ordered, so a screen picks one rather than
    /// inventing a sixth.
    func testAvatarSizesAreDistinctAndOrdered() {
        let sizes = [
            PlayerAvatar.Size.inline, PlayerAvatar.Size.roster, PlayerAvatar.Size.row,
            PlayerAvatar.Size.sheet, PlayerAvatar.Size.profile,
        ]
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }
}
