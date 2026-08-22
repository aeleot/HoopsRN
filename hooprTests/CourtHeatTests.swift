import XCTest
import SwiftUI
@testable import hoopr

/// Guards `CourtHeat.color(forGameCount:)` — the lookup that colours a court's
/// map pin by how busy it is today.
///
/// Worth pinning because it's a plain array index dressed up as a scale: an
/// off-by-one here silently reassigns which count gets which colour, and
/// nothing else would catch that before someone eyeballs the map.
final class CourtHeatTests: XCTestCase {

    private func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }

    /// Rec. 601 luma — enough to rank two colours by perceived brightness,
    /// which is all the scale below needs. Not a WCAG contrast figure;
    /// `ThemeContrastTests` owns those.
    private func luma(_ color: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Pinned to `hooprOrange`'s **light** value. `CourtHeat` hardcodes it
    /// rather than referencing the role (see the type's note on why), so this
    /// is the assertion that catches the two drifting apart silently.
    func testZeroGamesIsTheBrandOrange() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 0)), "F79331")
    }

    func testOneGameIsTheFirstOrangeStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 1)), "EB7A29")
    }

    func testTwoGamesIsTheSecondOrangeStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 2)), "DF6121")
    }

    func testThreeGamesIsTheThirdOrangeStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 3)), "D24718")
    }

    func testFourGamesIsTheReddishOrangeCeiling() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 4)), "C62E10")
    }

    /// The top stop is a ceiling, not a fourth-tier-only colour — a court
    /// hosting ten games today still reads as the same "very busy" red as one
    /// hosting exactly four, rather than falling off the end of the array.
    func testCountsAboveTheTopStopStayAtTheTopStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 4)), hex(CourtHeat.color(forGameCount: 40)))
    }

    /// Nothing today produces a negative count, but a lookup table should
    /// clamp rather than crash if one ever reached it.
    func testNegativeCountsClampToTheQuietestStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: -3)), hex(CourtHeat.color(forGameCount: 0)))
    }

    func testMaxTierMatchesTheStopCountUsedAbove() {
        XCTAssertEqual(CourtHeat.maxTier, 4)
    }

    /// Busier must always mean darker. The exact-hex tests above would catch
    /// *a* change, but only as "you edited this line" — they can't tell a
    /// deliberate retune that preserves the scale from one that accidentally
    /// makes "two games" lighter than "one game" and quietly turns the ramp
    /// into five unrelated oranges.
    func testEveryStopIsDarkerThanTheOneBeforeIt() {
        let lumas = (0...CourtHeat.maxTier).map { luma(CourtHeat.color(forGameCount: $0)) }
        for (index, pair) in zip(lumas, lumas.dropFirst()).enumerated() {
            XCTAssertGreaterThan(
                pair.0,
                pair.1,
                "stop \(index) should be lighter than stop \(index + 1)"
            )
        }
    }

    /// And the darkening should be *even*. A ramp that jumps hard between two
    /// stops and barely moves between two others reads as fewer tiers than it
    /// has — the eye groups the near-identical pair. 6 points of luma (out of
    /// 255) is a loose bound that still catches a stop dropped in without
    /// re-spacing its neighbours.
    func testTheStepsBetweenStopsAreEvenlySized() {
        let lumas = (0...CourtHeat.maxTier).map { luma(CourtHeat.color(forGameCount: $0)) * 255 }
        let steps = zip(lumas, lumas.dropFirst()).map { $0 - $1 }
        guard let smallest = steps.min(), let largest = steps.max() else {
            return XCTFail("expected at least two stops to compare")
        }
        XCTAssertLessThan(
            largest - smallest,
            6,
            "luma steps between stops are uneven: \(steps.map { Int($0.rounded()) })"
        )
    }
}
