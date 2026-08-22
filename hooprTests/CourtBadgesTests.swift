import XCTest
@testable import hoopr

/// Guards `CourtBadges.amenities(for:limit:)` — the narrowing the nearby list
/// applies when a court's name and its badges won't fit on one line together.
///
/// Worth pinning because the interesting rule is invisible at the call site:
/// the badges come back in display order with the "Restricted" caution *last*,
/// so the obvious implementation (`prefix(limit)`) sheds precisely the badge a
/// player most needs — the one saying they may not get on the court. Nothing
/// else in the app would catch that; the row would just quietly stop warning
/// people on exactly the courts where it matters.
final class CourtBadgesTests: XCTestCase {

    private func court(
        hoops: Int? = nil,
        surface: String? = nil,
        isLit: Bool? = nil,
        isCovered: Bool? = nil,
        access: Court.Access = .public
    ) -> Court {
        Court(
            id: "court-001",
            name: "Test Park Basketball Court",
            latitude: 35.9940,
            longitude: -78.8986,
            address: "Durham, NC",
            city: "Durham",
            hoops: hoops,
            surface: surface,
            isLit: isLit,
            isCovered: isCovered,
            access: access,
            osmType: "way",
            osmId: 123
        )
    }

    private func texts(_ amenities: [(text: String, isCaution: Bool)]) -> [String] {
        amenities.map(\.text)
    }

    /// The real worst case in `courts.json`: Bethesda Park, the only court in
    /// the dataset carrying four badges at once.
    private var fourBadgeCourt: Court {
        court(hoops: 2, surface: "concrete", isLit: true, isCovered: true)
    }

    func testNoLimitReturnsEveryBadge() {
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: fourBadgeCourt, limit: nil)),
            ["2 hoops", "Lit", "Covered", "Concrete"]
        )
    }

    func testALimitAboveTheBadgeCountChangesNothing() {
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: fourBadgeCourt, limit: 10)),
            ["2 hoops", "Lit", "Covered", "Concrete"]
        )
    }

    func testALimitDropsFromTheEndAndKeepsDisplayOrder() {
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: fourBadgeCourt, limit: 2)),
            ["2 hoops", "Lit"]
        )
    }

    /// The rule this suite exists for. "Restricted" sorts last for display, so
    /// it is the first thing a naive `prefix` would throw away — and it is the
    /// one badge that is a warning rather than a feature.
    func testTheRestrictedCautionSurvivesEvenAtALimitOfOne() {
        let restricted = court(
            hoops: 2,
            surface: "asphalt",
            isLit: true,
            access: .restricted
        )
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: restricted, limit: nil)),
            ["2 hoops", "Lit", "Asphalt", "Restricted"]
        )
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: restricted, limit: 1)),
            ["Restricted"]
        )
        // And at two it keeps the caution *plus* the highest-priority feature,
        // still in display order rather than caution-first.
        XCTAssertEqual(
            texts(CourtBadges.amenities(for: restricted, limit: 2)),
            ["2 hoops", "Restricted"]
        )
    }

    /// The bottom rung of `CourtRow`'s `ViewThatFits` ladder, which needs to
    /// render genuinely nothing so the name gets the whole line.
    func testALimitOfZeroReturnsNothingEvenWhenACautionIsPresent() {
        let restricted = court(hoops: 2, access: .restricted)
        XCTAssertTrue(CourtBadges.amenities(for: restricted, limit: 0).isEmpty)
    }

    func testACourtWithNoAmenitiesHasNoBadgesAtAnyLimit() {
        let bare = court()
        XCTAssertTrue(CourtBadges.amenities(for: bare, limit: nil).isEmpty)
        XCTAssertTrue(CourtBadges.amenities(for: bare, limit: 3).isEmpty)
    }
}
