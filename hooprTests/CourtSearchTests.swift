import XCTest
@testable import hoopr

/// Guards `CourtSearch`, which backs both the home-court picker and the map's
/// search field.
///
/// Two rules are load-bearing and easy to regress: **both** of a court's name
/// spellings are searched, and name matches outrank city matches. The first is
/// the one that was actually wrong before this existed — the picker searched
/// only the stored `name`, so a query spanning the stripped "Basketball Court"
/// boilerplate silently returned nothing.
final class CourtSearchTests: XCTestCase {

    private func court(
        id: String,
        name: String,
        city: String = "Durham"
    ) -> Court {
        Court(
            id: id,
            name: name,
            latitude: 35.9940,
            longitude: -78.8986,
            address: "\(city), NC",
            city: city,
            hoops: nil,
            surface: nil,
            isLit: nil,
            isCovered: nil,
            access: .public,
            osmType: nil,
            osmId: nil
        )
    }

    /// Stored name carries "Basketball Court"; `displayName` strips it.
    private var longMeadow: Court {
        court(id: "1", name: "Long Meadow Park Basketball Court #2")
    }

    // MARK: - Both name fields

    /// "Park #2" is only contiguous in `displayName` — the stored name has
    /// "Basketball Court" wedged into the middle of it. Matching `name` alone,
    /// which is what the picker used to do, missed this entirely.
    func testMatchesAQuerySpanningTheStrippedBoilerplate() {
        XCTAssertEqual(
            CourtSearch.matches([longMeadow], query: "Park #2").map(\.id),
            ["1"]
        )
    }

    /// The mirror image: "basketball" survives only in the stored `name`, so
    /// searching `displayName` alone would drop it. Both fields, or neither
    /// query works.
    func testMatchesAQueryForTheBoilerplateItself() {
        XCTAssertEqual(
            CourtSearch.matches([longMeadow], query: "basketball").map(\.id),
            ["1"]
        )
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(CourtSearch.matches([longMeadow], query: "LONG MEADOW").count, 1)
        XCTAssertEqual(CourtSearch.matches([longMeadow], query: "long meadow").count, 1)
    }

    /// "Long Meadow" appears in both spellings. An implementation that ran two
    /// filters and concatenated them would list this court twice.
    func testACourtMatchingBothSpellingsIsReturnedOnce() {
        XCTAssertEqual(CourtSearch.matches([longMeadow], query: "Long Meadow").count, 1)
    }

    // MARK: - Ranking

    /// Searching "Durham" hits one court's name and another's city. The named
    /// one has to come first, or typing a court's name buries it under every
    /// other court in the same town.
    func testNameMatchesRankAheadOfCityMatches() {
        let cityOnly = court(id: "city", name: "Lyon Park", city: "Durham")
        let named = court(id: "named", name: "Durham Central Park", city: "Raleigh")

        XCTAssertEqual(
            CourtSearch.matches([cityOnly, named], query: "Durham").map(\.id),
            ["named", "city"]
        )
    }

    func testACityMatchSurfacesWhenNoNameMatches() {
        let court = court(id: "1", name: "Lyon Park", city: "Chapel Hill")
        XCTAssertEqual(CourtSearch.matches([court], query: "Chapel").map(\.id), ["1"])
    }

    // MARK: - Empty and bounds

    /// Nothing, not everything — a suggestion list shows no rows before the
    /// user has typed rather than the whole 214-court dataset.
    func testABlankQueryReturnsNothing() {
        XCTAssertTrue(CourtSearch.matches([longMeadow], query: "").isEmpty)
        XCTAssertTrue(CourtSearch.matches([longMeadow], query: "   ").isEmpty)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(CourtSearch.matches([longMeadow], query: "  Long Meadow  ").count, 1)
    }

    func testHonoursTheLimit() {
        let courts = (0..<40).map { court(id: "\($0)", name: "Park \($0)") }
        XCTAssertEqual(CourtSearch.matches(courts, query: "Park", limit: 5).count, 5)
        XCTAssertEqual(
            CourtSearch.matches(courts, query: "Park").count,
            CourtSearch.defaultLimit
        )
    }

    /// `prefix` would happily trap on a negative bound, so the guard is real.
    func testANonPositiveLimitReturnsNothing() {
        XCTAssertTrue(CourtSearch.matches([longMeadow], query: "Long", limit: 0).isEmpty)
        XCTAssertTrue(CourtSearch.matches([longMeadow], query: "Long", limit: -1).isEmpty)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(CourtSearch.matches([longMeadow], query: "Raleigh").isEmpty)
    }
}
