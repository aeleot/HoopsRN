import XCTest
import SwiftUI
@testable import hoopr

/// Guards the one property a token layer exists to have: that a *role* is a
/// step on the *scale*, rather than a number that merely looks like one.
///
/// The values themselves aren't pinned — asserting `pageMargin == 20` would
/// just restate `Spacing.swift` and fail on every legitimate retune. What is
/// worth holding is the relationship, because that is what Phase 6's
/// consolidation could quietly break: a role retuned to 18 stops being on the
/// grid and nothing else would notice.
final class SpacingTests: XCTestCase {

    func testTheScaleIsStrictlyIncreasing() {
        for (lower, upper) in zip(Spacing.scale, Spacing.scale.dropFirst()) {
            XCTAssertLessThan(lower, upper, "Spacing.scale must be in strictly increasing order")
        }
    }

    /// Every role that claims to be a step is one. `Chip` is left out on
    /// purpose: 14 × 9 is optically tuned against its 13pt label and is
    /// documented as off the scale, so asserting it here would be asserting the
    /// opposite of what `Spacing.Chip` says.
    func testEveryRoleThatIsMeantToBeOnTheScaleIsAStepOnIt() {
        let roles: [(String, CGFloat)] = [
            ("pageMargin", Spacing.pageMargin),
            ("cardPadding", Spacing.cardPadding),
            ("interCard", Spacing.interCard),
            ("interRow", Spacing.interRow),
            ("section", Spacing.section),
            ("Pill.horizontal", Spacing.Pill.horizontal),
            ("Pill.vertical", Spacing.Pill.vertical),
        ]

        for (name, value) in roles {
            XCTAssertTrue(
                Spacing.scale.contains(value),
                "Spacing.\(name) is \(value), which isn't a step on Spacing.scale \(Spacing.scale)"
            )
        }
    }

    /// The relationships a layout depends on, which hold under any retune that
    /// stays sensible: a card's contents are never inset further than the page
    /// insets the card; a screen's sections sit further apart than the cards
    /// within one; a list's rows sit no further apart than a screen's cards.
    func testTheRolesKeepTheirRelativeOrder() {
        XCTAssertGreaterThanOrEqual(Spacing.pageMargin, Spacing.cardPadding)
        XCTAssertGreaterThan(Spacing.section, Spacing.interCard)
        XCTAssertLessThanOrEqual(Spacing.interRow, Spacing.interCard)
    }
}
