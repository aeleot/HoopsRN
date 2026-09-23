import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Pins the type ladder `HooprTextRole` defines.
///
/// The roles exist because the app grew six spellings of one uppercase section
/// label at two sizes and two weights. A table that isn't asserted drifts back
/// into that, and the failure is invisible — nothing crashes when a heading is
/// 13pt in one place and 12pt in another.
///
/// The scaled sizes below are **measured values**, not estimates: they are what
/// `UIFontMetrics` produces at `accessibilityExtraLarge` through the same
/// `HooprFontMetrics.metricsStyle(for:)` ladder the modifier runs. They are
/// asserted because the *relationship between them* is what the redesign's
/// hierarchy rests on, and because a change to `metricsStyle`'s boundaries
/// would silently move a hero onto a different scaling curve.
final class TypeRoleTests: XCTestCase {

    private let axl = UIContentSizeCategory.accessibilityExtraLarge

    private func scaled(_ role: HooprTextRole) -> CGFloat {
        HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: axl)
    }

    // MARK: - The ladder

    func testEveryRoleIsDistinctAndDescends() {
        let ordered: [HooprTextRole] = [.numeral, .display, .title, .headline, .subhead, .body, .caption, .label, .badge]

        XCTAssertEqual(
            Set(ordered), Set(HooprTextRole.allCases),
            "a role was added without being placed in the ladder"
        )

        for (larger, smaller) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThan(
                larger.size, smaller.size,
                "\(larger) should be larger than \(smaller)"
            )
        }
    }

    /// The measured ladder at `.accessibility3`, to one decimal.
    func testScaledSizesAtAccessibility3() {
        let expected: [(HooprTextRole, CGFloat)] = [
            (.numeral, 65.33), (.display, 59.67), (.title, 47.0), (.headline, 40.67),
            (.subhead, 37.0), (.body, 32.33), (.caption, 29.0),
            (.label, 16.0), (.badge, 14.0),
        ]

        for (role, size) in expected {
            XCTAssertEqual(
                scaled(role), size, accuracy: 0.05,
                "\(role) scales to \(scaled(role))pt, expected \(size)pt"
            )
        }
    }

    /// **The finding the redesign's layering rests on.** The smallest roles
    /// scale hardest, so the distance between the hero and the supporting text
    /// shrinks at exactly the size where a reader most needs the hierarchy.
    /// If this ever stops being true the band can stop carrying rank — and if
    /// it gets *worse*, the band matters more, not less.
    func testHierarchyCompressesAtAccessibilitySizes() {
        let defaultRatio = HooprTextRole.numeral.size / HooprTextRole.caption.size
        let scaledRatio = scaled(.numeral) / scaled(.caption)

        XCTAssertEqual(defaultRatio, 3.38, accuracy: 0.02)
        XCTAssertEqual(scaledRatio, 2.25, accuracy: 0.02)
        XCTAssertLessThan(
            scaledRatio, defaultRatio,
            "the ladder is expected to compress; if it stopped, the reason the hero sits in a band changed"
        )
    }

    // MARK: - Caps

    /// Only the two roles that live inside frames which can't grow are capped.
    /// A cap anywhere else is a clipped word at the accessibility sizes.
    func testOnlyTheUppercaseRolesCap() {
        for role in HooprTextRole.allCases {
            if role == .label || role == .badge {
                XCTAssertNotNil(role.maximumSize, "\(role) sits in a fixed frame and must cap")
            } else {
                XCTAssertNil(
                    role.maximumSize,
                    "\(role) must reflow, not cap — a cap here clips the screen's answer"
                )
            }
        }
    }

    /// The capped roles end up *smaller* than body text at `.accessibility3`
    /// (16 and 14 against 32.3). That is correct — they are chrome inside
    /// capsules — but it means a label can no longer be told from content by
    /// size there, which is why the label's job is carried by case and colour
    /// too.
    func testCappedRolesFallBelowBodyTextAtAccessibilitySizes() {
        XCTAssertLessThan(scaled(.label), scaled(.body))
        XCTAssertLessThan(scaled(.badge), scaled(.body))
    }

    // MARK: - Treatments

    func testOnlyTheNumeralTierUsesTabularFigures() {
        for role in HooprTextRole.allCases {
            XCTAssertEqual(
                role.usesTabularFigures, role == .numeral,
                "\(role): tabular figures belong only to the numeral tier"
            )
        }
    }

    func testOnlyLabelAndBadgeAreUppercased() {
        for role in HooprTextRole.allCases {
            let expected = role == .label || role == .badge
            XCTAssertEqual(role.isUppercase, expected, "\(role)")
            XCTAssertEqual(
                role.kerning > 0, expected,
                "\(role): kerning is part of the uppercase treatment and nothing else"
            )
        }
    }

    /// Every role resolves through `hooprFont`, so `HooprFontMetrics` stays the
    /// only place the app does size arithmetic (constraint 2).
    func testEveryRoleScalesOnTheSharedCurve() {
        for role in HooprTextRole.allCases {
            let direct = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: axl)
            XCTAssertEqual(scaled(role), direct, accuracy: 0.001, "\(role)")
        }
    }
}
