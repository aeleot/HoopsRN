import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Pins the map's name-shortening rule (`CourtName`): a name that doesn't fit
/// sheds a trailing "Park", then its court number, and only then is cut.
///
/// Set by the user on 2026-09-22 — the full name is what the Runs tab shows —
/// and worth pinning because the rule has one way to go quietly wrong: dropping
/// a "Park" that is part of the place. Four names in the dataset carry it
/// mid-name, and removing it from "Lake Park Trail" names somewhere else.
@MainActor
final class CourtNameTests: XCTestCase {

    // MARK: - The ladder

    func testATrailingParkGoesFirst() {
        XCTAssertEqual(CourtName.forms(of: "East End Park"), ["East End Park", "East End"])
    }

    /// "Park" goes before the number, because the number is what tells
    /// sibling courts apart — "Long Meadow Park #1" and "#3" are different
    /// courts, and "Long Meadow Park" would name neither.
    func testParkGoesBeforeTheCourtNumber() {
        XCTAssertEqual(
            CourtName.forms(of: "Long Meadow Park #3"),
            ["Long Meadow Park #3", "Long Meadow #3", "Long Meadow"]
        )
    }

    func testANumberWithoutAParkStillGoes() {
        XCTAssertEqual(CourtName.forms(of: "Apex #10"), ["Apex #10", "Apex"])
    }

    func testAParkMidNameIsPartOfThePlace() {
        for name in ["Lake Park Trail", "Ting Park Soccer Field A", "Halifax Park Outdoor"] {
            XCTAssertEqual(CourtName.forms(of: name), [name], "\"\(name)\" must keep its Park")
        }
    }

    /// A name that is nothing but the word — or the number — keeps it:
    /// shortening to nothing is not a shorter name.
    func testANameIsNeverShortenedToNothing() {
        XCTAssertEqual(CourtName.forms(of: "Park"), ["Park"])
        XCTAssertEqual(CourtName.forms(of: "#4"), ["#4"])
        XCTAssertEqual(CourtName.forms(of: "Park #4"), ["Park #4", "Park"])
    }

    func testANameWithNothingToShedHasOneForm() {
        XCTAssertEqual(CourtName.forms(of: "George Watts Playground"), ["George Watts Playground"])
    }

    // MARK: - Across the dataset

    /// Every form of every shipped name is non-empty, each step is strictly
    /// shorter than the last, and no step removes a word other than a trailing
    /// "Park" or a `#N` — so the ladder only ever sheds what it says it does.
    func testEveryShippedNameShortensOnlyTheWayTheRuleSays() throws {
        let names = CourtService().courts.map(\.displayName)
        try XCTSkipIf(names.isEmpty, "courts.json not reachable from the test host")

        for name in Set(names) {
            let forms = CourtName.forms(of: name)
            XCTAssertEqual(forms.first, name)

            for (longer, shorter) in zip(forms, forms.dropFirst()) {
                XCTAssertFalse(shorter.isEmpty, "\"\(name)\" shortened to nothing")
                XCTAssertLessThan(shorter.count, longer.count, "\"\(name)\"")

                let removed = Set(longer.split(separator: " ")).subtracting(shorter.split(separator: " "))
                for word in removed {
                    XCTAssertTrue(
                        word.lowercased() == "park" || (word.hasPrefix("#") && word.dropFirst().allSatisfy(\.isNumber)),
                        "\"\(name)\" lost \"\(word)\", which is neither a trailing Park nor a court number"
                    )
                }
            }
        }
    }
}
