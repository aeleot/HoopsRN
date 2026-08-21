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

    func testZeroGamesIsLightSkyBlue() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 0)), "C3E6FC")
    }

    func testOneGameIsTheFirstAmberStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 1)), "FFD131")
    }

    func testTwoGamesIsTheSecondAmberStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 2)), "F5B82E")
    }

    func testThreeGamesIsTheThirdAmberStop() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 3)), "F4AC32")
    }

    func testFourGamesIsDeepRed() {
        XCTAssertEqual(hex(CourtHeat.color(forGameCount: 4)), "B90E0A")
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
}
