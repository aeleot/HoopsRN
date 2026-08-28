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
