import XCTest
import CoreGraphics
@testable import hoopr

/// The map sheet's detent machine — the densest interaction code in the app,
/// and until now the only part of it with no coverage at all (`GAPS.md`).
///
/// It went untested because every rule lived in `private` members of a `View`,
/// reachable only through a real drag. Extracting the arithmetic into
/// `SheetGeometry` is what made these assertions possible; the gestures and the
/// animation stay in `MapTab`, where a test wouldn't have helped anyway.
final class MapTabDetentTests: XCTestCase {

    /// An iPhone 17-ish tab height net of the floating tab bar.
    private let geometry = SheetGeometry(containerHeight: 769)

    /// What `containerHeight` collapses to once the keyboard takes the bottom
    /// safe area. The sheet has to stay coherent at this size — it's the state
    /// the search field puts the screen into.
    private let keyboardGeometry = SheetGeometry(containerHeight: 433)

    // MARK: - Heights

    func testExpandedStopsBelowTheMeasuredBandAndGap() {
        let band = SheetGeometry(containerHeight: 729, topInset: 232)
        XCTAssertEqual(band.expandedHeight, 497)
        XCTAssertEqual(band.mediumHeight, 243)
    }

    func testSmallBandKeepsTheOriginalExpandedFraction() {
        XCTAssertEqual(SheetGeometry(containerHeight: 729, topInset: 80).expandedHeight, 729 * 0.78)
    }

    func testLargeBandAndKeyboardKeepTheDetentsOrdered() {
        for inset: CGFloat in [250, 400, 500] {
            let sheet = SheetGeometry(containerHeight: 400, fittedMediumHeight: 500, topInset: inset)
            XCTAssertGreaterThanOrEqual(sheet.expandedHeight, 0)
            XCTAssertLessThanOrEqual(sheet.mediumHeight, sheet.expandedHeight)
            XCTAssertLessThanOrEqual(sheet.restingMediumHeight, sheet.expandedHeight)
            XCTAssertLessThanOrEqual(sheet.sheetHeight(detent: .expanded, drag: -500), max(0, 400 - inset))
        }
    }

    func testMediumIsAThirdAndExpandedIsMostOfTheContainer() {
        XCTAssertEqual(geometry.mediumHeight, 769 / 3, accuracy: 0.001)
        XCTAssertEqual(geometry.expandedHeight, 769 * 0.78, accuracy: 0.001)
    }

    /// Collapsed and medium share a base height; only the offset differs. The
    /// sheet leaves the screen by sliding, not by shrinking to nothing.
    func testCollapsedAndMediumShareABaseHeight() {
        XCTAssertEqual(
            geometry.baseHeight(for: .collapsed),
            geometry.baseHeight(for: .medium)
        )
    }

    func testSheetHeightIsClampedToTheDetentRange() {
        // A huge upward drag can't grow the sheet past expanded...
        XCTAssertEqual(
            geometry.sheetHeight(detent: .expanded, drag: -10_000),
            geometry.expandedHeight,
            accuracy: 0.001
        )
        // ...and a huge downward one can't shrink it below medium.
        XCTAssertEqual(
            geometry.sheetHeight(detent: .medium, drag: 10_000),
            geometry.mediumHeight,
            accuracy: 0.001
        )
    }

    /// The clamp has to hold at the keyboard-shrunk size too, where medium and
    /// expanded are much closer together.
    func testSheetHeightIsClampedWithTheKeyboardUp() {
        let height = keyboardGeometry.sheetHeight(detent: .expanded, drag: -5_000)
        XCTAssertEqual(height, keyboardGeometry.expandedHeight, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(height, keyboardGeometry.mediumHeight)
    }

    // MARK: - Offset

    func testARestingSheetHasNoOffsetExceptWhenCollapsed() {
        XCTAssertEqual(geometry.sheetOffset(detent: .medium, drag: 0), 0, accuracy: 0.001)
        XCTAssertEqual(geometry.sheetOffset(detent: .expanded, drag: 0), 0, accuracy: 0.001)
        XCTAssertEqual(
            geometry.sheetOffset(detent: .collapsed, drag: 0),
            geometry.mediumHeight,
            accuracy: 0.001
        )
    }

    /// Between medium and expanded the sheet *grows* rather than sliding, so
    /// dragging up from medium must not move it off its anchor.
    func testDraggingUpFromMediumChangesHeightNotOffset() {
        XCTAssertEqual(geometry.sheetOffset(detent: .medium, drag: -80), 0, accuracy: 0.001)
        XCTAssertGreaterThan(
            geometry.sheetHeight(detent: .medium, drag: -80),
            geometry.mediumHeight
        )
    }

    // MARK: - Rubber banding

    func testCollapseProgressClampsAtBothEndsOfTravel() {
        XCTAssertEqual(geometry.collapseProgress(offset: -40), 0)
        XCTAssertEqual(geometry.collapseProgress(offset: 0), 0)
        XCTAssertEqual(geometry.collapseProgress(offset: geometry.restingMediumHeight / 2), 0.5)
        XCTAssertEqual(geometry.collapseProgress(offset: geometry.restingMediumHeight), 1)
        XCTAssertEqual(geometry.collapseProgress(offset: geometry.restingMediumHeight + 40), 1)
    }

    func testCollapseProgressUsesTheFittedCardHeight() {
        let fitted = SheetGeometry(containerHeight: 769, fittedMediumHeight: 400)
        XCTAssertEqual(fitted.collapseProgress(offset: 200), 0.5)
        XCTAssertEqual(fitted.collapseProgress(offset: 400), 1)
        XCTAssertEqual(SheetGeometry(containerHeight: 0).collapseProgress(offset: 10), 0)
    }

    func testContentFadesDuringOnlyTheFirstFortyPercent() {
        XCTAssertEqual(SheetGeometry.contentOpacity(collapseProgress: -0.2), 1)
        XCTAssertEqual(SheetGeometry.contentOpacity(collapseProgress: 0), 1)
        XCTAssertEqual(SheetGeometry.contentOpacity(collapseProgress: 0.2), 0.5)
        for progress: CGFloat in [0.4, 0.6, 1, 1.2] {
            XCTAssertEqual(SheetGeometry.contentOpacity(collapseProgress: progress), 0)
        }
    }

    func testReversingCollapseRetracesTheSameOpacity() {
        let progress: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.4, 0.6, 1]
        let down = progress.map { SheetGeometry.contentOpacity(collapseProgress: $0) }
        let up = progress.reversed().map { SheetGeometry.contentOpacity(collapseProgress: $0) }
        XCTAssertEqual(down, up.reversed())
    }

    /// However hard it's flung, the overshoot eases toward the limit and stops.
    ///
    /// The bound is asserted inclusively on purpose: `resistance` approaches its
    /// limit asymptotically in the maths, but `exp(-overshoot / limit)`
    /// underflows to exactly zero for a large enough drag, so in `CGFloat` the
    /// result *lands on* the limit rather than creeping up to it. Either way the
    /// sheet can't be dragged past it, which is the property that matters.
    func testRubberBandingIsBoundedByItsLimit() {
        let far = geometry.rubberBanded(geometry.mediumHeight + 100_000)
        XCTAssertLessThanOrEqual(far, geometry.mediumHeight + SheetGeometry.rubberBandLimit)
        XCTAssertGreaterThan(far, geometry.mediumHeight)

        let above = geometry.rubberBanded(-100_000)
        XCTAssertGreaterThanOrEqual(above, -SheetGeometry.rubberBandLimit)
        XCTAssertLessThan(above, 0)
    }

    func testRubberBandingIsTheIdentityInsideTheTravelRange() {
        XCTAssertEqual(geometry.rubberBanded(0), 0, accuracy: 0.001)
        XCTAssertEqual(geometry.rubberBanded(50), 50, accuracy: 0.001)
        XCTAssertEqual(
            geometry.rubberBanded(geometry.mediumHeight),
            geometry.mediumHeight,
            accuracy: 0.001
        )
    }

    func testRubberBandingIsMonotonic() {
        var previous = geometry.rubberBanded(0)
        for offset in stride(from: CGFloat(10), through: 2_000, by: 10) {
            let current = geometry.rubberBanded(offset)
            XCTAssertGreaterThanOrEqual(current, previous)
            previous = current
        }
    }

    func testResistanceStartsAtZeroAndNeverExceedsTheLimit() {
        XCTAssertEqual(SheetGeometry.resistance(0), 0, accuracy: 0.001)
        // Saturates at the limit rather than passing it — see the note above.
        XCTAssertLessThanOrEqual(
            SheetGeometry.resistance(1_000_000),
            SheetGeometry.rubberBandLimit
        )
        // A realistic overshoot is still strictly inside the bound, which is
        // what makes the drag feel like it's resisting rather than stopping.
        XCTAssertLessThan(SheetGeometry.resistance(60), SheetGeometry.rubberBandLimit)
    }

    // MARK: - One detent per gesture

    /// A hard fling must not skip a detent — from expanded you land on medium,
    /// never straight off the bottom of the screen.
    func testAFlingMovesOneDetentAtMost() {
        XCTAssertEqual(SheetGeometry.nextDetent(from: .expanded, projecting: 10_000), .medium)
        XCTAssertEqual(SheetGeometry.nextDetent(from: .medium, projecting: 10_000), .collapsed)
        XCTAssertEqual(SheetGeometry.nextDetent(from: .collapsed, projecting: -10_000), .medium)
        XCTAssertEqual(SheetGeometry.nextDetent(from: .medium, projecting: -10_000), .expanded)
    }

    func testTravelBelowTheThresholdStaysPut() {
        let short = SheetGeometry.detentThreshold - 1
        for detent in SheetDetent.allCases {
            XCTAssertEqual(SheetGeometry.nextDetent(from: detent, projecting: short), detent)
            XCTAssertEqual(SheetGeometry.nextDetent(from: detent, projecting: -short), detent)
            XCTAssertEqual(SheetGeometry.nextDetent(from: detent, projecting: 0), detent)
        }
    }

    /// The ends of the range don't wrap around.
    func testTheDetentRangeHasHardEnds() {
        XCTAssertEqual(SheetGeometry.nextDetent(from: .expanded, projecting: -10_000), .expanded)
        XCTAssertEqual(SheetGeometry.nextDetent(from: .collapsed, projecting: 10_000), .collapsed)
    }

    // MARK: - A court card's fitted medium

    /// The map's container on an iPhone 17 once the map stopped above the tab
    /// bar: `.medium` is ~215pt, which left a court card ~112pt to scroll —
    /// the name and distance, then half a run.
    private let cardGeometry = SheetGeometry(containerHeight: 645)

    private func fitted(_ height: CGFloat?) -> SheetGeometry {
        SheetGeometry(containerHeight: cardGeometry.containerHeight, fittedMediumHeight: height)
    }

    /// The list, and a card that hasn't measured yet, rest at a third.
    func testWithoutAFittedHeightMediumIsStillAThird() {
        XCTAssertEqual(fitted(nil).restingMediumHeight, cardGeometry.mediumHeight)
        XCTAssertEqual(fitted(nil).sheetHeight(detent: .medium, drag: 0), 215, accuracy: 0.5)
    }

    /// A card whose lead needs more than a third rests tall enough to show it
    /// — the fix for a run cut in half at `.medium`.
    func testACardThatNeedsMoreRoomRestsTallerAtMedium() {
        let geometry = fitted(262)
        XCTAssertEqual(geometry.sheetHeight(detent: .medium, drag: 0), 262)
        XCTAssertEqual(geometry.sheetOffset(detent: .medium, drag: 0), 0)
    }

    /// A card with only a name and "No runs here today" keeps the list's
    /// height — it never rests *shorter* than a third.
    func testACardThatNeedsLessRoomKeepsTheListsHeight() {
        XCTAssertEqual(fitted(180).restingMediumHeight, cardGeometry.mediumHeight)
    }

    /// A card taller than the expanded sheet (huge text, a long waitlist note)
    /// is capped there, and scrolls.
    func testAFittedHeightNeverExceedsExpanded() {
        XCTAssertEqual(fitted(900).restingMediumHeight, cardGeometry.expandedHeight)
    }

    /// Dragging a taller card down stops at its own resting height before the
    /// sheet starts to leave the screen, exactly as the list does at a third.
    func testDraggingAFittedCardDownFloorsAtItsRestingHeight() {
        let geometry = fitted(262)
        XCTAssertEqual(geometry.sheetHeight(detent: .expanded, drag: 10_000), 262)
        XCTAssertEqual(geometry.sheetOffset(detent: .medium, drag: 30), 30)
    }

    // MARK: - Display detent

    /// The bug this rule exists for: a court tapped while the list sits
    /// collapsed would otherwise inherit that offset and render off-screen.
    func testADetailCardNeverRendersCollapsed() {
        let state = SheetState.detail(court: Self.court, returningTo: .collapsed)
        XCTAssertEqual(state.displayDetent, .medium)
        // ...but it still remembers where to go back to.
        XCTAssertEqual(state.detent, .collapsed)
    }

    /// Everything other than collapsed keeps its height, so tapping a court
    /// from a full-height list doesn't shrink the sheet under your thumb.
    func testADetailCardKeepsAnExpandedSheetExpanded() {
        let state = SheetState.detail(court: Self.court, returningTo: .expanded)
        XCTAssertEqual(state.displayDetent, .expanded)
        XCTAssertEqual(state.detent, .expanded)
    }

    func testARestingSheetDisplaysAtItsOwnDetent() {
        for detent in SheetDetent.allCases {
            XCTAssertEqual(SheetState.rest(detent).displayDetent, detent)
            XCTAssertEqual(SheetState.rest(detent).detent, detent)
        }
    }

    func testOnlyADetailStateCarriesACourt() {
        XCTAssertNil(SheetState.rest(.medium).selectedCourt)
        XCTAssertEqual(
            SheetState.detail(court: Self.court, returningTo: .medium).selectedCourt?.id,
            Self.court.id
        )
    }

    // MARK: - The band while a court is open (design critique, 2026-10-09)

    /// With a court open the band is its label row alone, at every detent the
    /// card can return to.
    func testAnOpenCourtCompactsTheBand() {
        for detent in SheetDetent.allCases {
            let state = SheetState.detail(court: Self.court, returningTo: detent)
            XCTAssertEqual(MapBandLayout.layout(for: state, isSearching: false), .compact, "\(detent)")
        }
        XCTAssertFalse(MapBandLayout.compact.showsSearch)
    }

    /// Closing the card brings the search field and chips back, whichever
    /// detent the sheet returns to.
    func testLeavingTheDetailRestoresTheFullBand() {
        for detent in SheetDetent.allCases {
            let open = SheetState.detail(court: Self.court, returningTo: detent)
            let closed = SheetState.rest(open.detent)

            XCTAssertEqual(MapBandLayout.layout(for: open, isSearching: false), .compact)
            XCTAssertEqual(MapBandLayout.layout(for: closed, isSearching: false), .full, "\(detent)")
        }
        XCTAssertTrue(MapBandLayout.full.showsSearch)
    }

    /// Search outranks the card, as it does in the sheet: while the field has
    /// the keyboard or a query, the field stays where the user is typing.
    func testSearchKeepsTheFullBandWithACourtOpen() {
        let open = SheetState.detail(court: Self.court, returningTo: .medium)
        XCTAssertEqual(MapBandLayout.layout(for: open, isSearching: true), .full)
        XCTAssertEqual(MapBandLayout.layout(for: .rest(.medium), isSearching: true), .full)
    }

    /// iPhone 17, measured from the live app on 2026-10-09: a 729pt tab, a
    /// full band of 170pt, a compact one of 72pt, and a hosted run's card
    /// resting at ~275pt under either — 283pt of map before, 382pt after. The
    /// card rests exactly where it did, so **every point the band gives up is
    /// map.**
    private let tabHeight: CGFloat = 729
    private let fullBand: CGFloat = 170
    private let compactBand: CGFloat = 72
    private let hostedRunCard: CGFloat = 275

    private func withBand(_ band: CGFloat) -> SheetGeometry {
        SheetGeometry(containerHeight: tabHeight, fittedMediumHeight: hostedRunCard, topInset: band + 12)
    }

    func testACompactBandHandsItsHeightToTheMap() {
        XCTAssertEqual(withBand(fullBand).visibleMapHeight(bandHeight: fullBand, detent: .medium, drag: 0), 284)
        XCTAssertEqual(withBand(compactBand).visibleMapHeight(bandHeight: compactBand, detent: .medium, drag: 0), 382)
        XCTAssertEqual(
            withBand(compactBand).sheetHeight(detent: .medium, drag: 0),
            withBand(fullBand).sheetHeight(detent: .medium, drag: 0),
            "the card rests at the same height under either band"
        )
        XCTAssertEqual(
            withBand(compactBand).visibleMapHeight(bandHeight: compactBand, detent: .medium, drag: 0)
                - withBand(fullBand).visibleMapHeight(bandHeight: fullBand, detent: .medium, drag: 0),
            fullBand - compactBand
        )
    }

    /// The full band held an expanded card 12pt under itself, below the 0.78
    /// cap; with the compact band the cap is what stops it.
    func testACompactBandLetsAnExpandedCardRiseToItsCap() {
        XCTAssertEqual(withBand(fullBand).expandedHeight, tabHeight - fullBand - 12)
        XCTAssertEqual(withBand(compactBand).expandedHeight, tabHeight * 0.78, accuracy: 0.001)
    }

    /// The visible map never goes negative, however tall the band or the sheet.
    func testTheVisibleMapIsNeverNegative() {
        XCTAssertEqual(withBand(fullBand).visibleMapHeight(bandHeight: 900, detent: .expanded, drag: 0), 0)
        XCTAssertEqual(geometry.visibleMapHeight(bandHeight: -10, detent: .collapsed, drag: 0), geometry.containerHeight)
    }

    /// What's on screen is the sheet less its slide: all of it at rest, none
    /// of it collapsed — the number the map's framing and the recenter
    /// button read.
    func testTheVisibleSheetIsItsHeightLessItsSlide() {
        XCTAssertEqual(geometry.visibleHeight(detent: .medium, drag: 0), geometry.mediumHeight)
        XCTAssertEqual(geometry.visibleHeight(detent: .expanded, drag: 0), geometry.expandedHeight)
        XCTAssertEqual(geometry.visibleHeight(detent: .collapsed, drag: 0), 0)
        XCTAssertEqual(geometry.visibleHeight(detent: .medium, drag: 50), geometry.mediumHeight - 50)
    }

    // MARK: - Clearance above the tab bar

    /// **No pane's last row sits closer than `Spacing.md` to the tab bar.** The
    /// lists keep exactly that under their last row; the court card keeps more
    /// under its buttons. The bar's glass starts at this container's bottom
    /// edge, so these insets are the whole gap.
    @MainActor
    func testNoPaneSitsCloserThanSpacingMdToTheTabBar() {
        XCTAssertEqual(SheetGeometry.bottomClearance, Spacing.md)
        XCTAssertGreaterThanOrEqual(SheetGeometry.cardActionsBottomInset, SheetGeometry.bottomClearance)
    }

    private static let court = Court(
        id: "court-001",
        name: "Long Meadow Park Basketball Court",
        latitude: 35.9940,
        longitude: -78.8986,
        address: "Durham, NC",
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
