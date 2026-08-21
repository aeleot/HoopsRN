import XCTest
@testable import hoopr

/// Guards `Court.displayName`, the one piece of derivation the `Court` model
/// carries.
///
/// It's worth pinning because six screens render it — the map's detail card,
/// the nearby list, the Local Runs cards, the create-run form, the home-court
/// picker and another player's profile — and because the rule is a string
/// substitution, which is exactly the kind of thing that quietly starts
/// mangling names when the dataset's naming changes.
final class CourtTests: XCTestCase {

    private func court(named name: String) -> Court {
        Court(
            id: "court-001",
            name: name,
            latitude: 35.9940,
            longitude: -78.8986,
            address: "Durham, NC",
            city: "Durham",
            hoops: 2,
            surface: "asphalt",
            isLit: true,
            isCovered: false,
            access: .public,
            osmType: "way",
            osmId: 123
        )
    }

    func testStripsTheDatasetBoilerplate() {
        XCTAssertEqual(
            court(named: "George Watts Playground Basketball Court").displayName,
            "George Watts Playground"
        )
    }

    /// The numbered suffix is the only thing distinguishing sibling courts in
    /// the same park, so it has to survive stripping the words in front of it.
    func testKeepsATrailingNumberedSuffix() {
        XCTAssertEqual(
            court(named: "Long Meadow Park Basketball Court #2").displayName,
            "Long Meadow Park #2"
        )
    }

    func testCollapsesTheWhitespaceStrippingLeavesBehind() {
        XCTAssertEqual(
            court(named: "Red  Maple Basketball Court   #1").displayName,
            "Red Maple #1"
        )
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(
            court(named: "Oval Drive Park basketball court").displayName,
            "Oval Drive Park"
        )
    }

    /// A court named only after its type would strip to nothing, which would
    /// render an empty row. The stored name is the fallback.
    func testFallsBackToTheStoredNameWhenStrippingLeavesNothing() {
        XCTAssertEqual(court(named: "Basketball Court").displayName, "Basketball Court")
    }

    func testLeavesANameWithoutTheBoilerplateAlone() {
        XCTAssertEqual(court(named: "The Cage").displayName, "The Cage")
    }
}
