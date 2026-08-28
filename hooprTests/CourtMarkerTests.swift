import XCTest
@testable import hoopr

/// Guards the pin badge's count rule.
///
/// Worth pinning because it deliberately *disagrees* with `CourtHeat`, which
/// ceilings at 4 — and "make these consistent" is a plausible-sounding change
/// that would quietly throw away information. The colour stops distinguishing
/// at 4 because it runs out of luma; the number has no such limit, and it is
/// the reason the badge exists.
final class CourtMarkerTests: XCTestCase {

    func testSmallCountsAreExact() {
        XCTAssertEqual(CourtMarkerView.countText(1), "1")
        XCTAssertEqual(CourtMarkerView.countText(4), "4")
        XCTAssertEqual(CourtMarkerView.countText(9), "9")
    }

    /// Past 9 the numeral stops fitting a 27pt disc, which is a legibility
    /// limit rather than a data one — so it truncates here and nowhere earlier.
    func testCountsPastNineAreTruncated() {
        XCTAssertEqual(CourtMarkerView.countText(10), "9+")
        XCTAssertEqual(CourtMarkerView.countText(99), "9+")
    }

    /// The badge is hidden at zero rather than drawing "0", but the function
    /// still has to answer — `configureAsCourt` calls it before deciding.
    func testZeroIsStillFormatted() {
        XCTAssertEqual(CourtMarkerView.countText(0), "0")
    }

    /// The count exceeds `CourtHeat`'s ramp on purpose: a court with 7 runs and
    /// one with 4 share a colour but must not share a badge.
    func testTheCountOutlivesTheColourRamp() {
        XCTAssertNotEqual(
            CourtMarkerView.countText(CourtHeat.maxTier),
            CourtMarkerView.countText(CourtHeat.maxTier + 3)
        )
    }
}
