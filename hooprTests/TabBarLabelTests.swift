import SwiftUI
import UIKit
import XCTest
@testable import hoopr

/// Renders the app's tab bar at large Dynamic Type and fails if a label is too
/// wide for the space it gets.
///
/// Four tabs is the practical ceiling before labels start clipping, and Seasons
/// took the fourth slot — so "Seasons" over the shorter "Squad" was a decision
/// that needed evidence rather than taste. This is that evidence, kept as a
/// test so a fifth tab, a longer label, or an iOS layout change fails here
/// instead of on somebody's phone.
///
/// **What the measurement actually showed, because it's not what you'd guess:**
/// `UITabBar` *clamps* its own content size category. With the hosting
/// controller overridden to `.accessibility3`, the tab bar's labels report
/// `XXL` and render at 10pt — the bar caps Dynamic Type for its titles and
/// offers the large-content-viewer HUD (long-press) at accessibility sizes
/// instead of growing them. So the labels never reach the size that would clip
/// them, which is exactly why the native bar was adopted over the hand-rolled
/// header that needed `minimumScaleFactor`.
///
/// That clamp is UIKit's, not ours, so this asserts the *outcome* — every label
/// fits its share of the narrowest screen — rather than the clamp itself. If a
/// future iOS stops clamping, the labels grow, and this fails.
///
/// It builds a bare `TabView` with the same four titles rather than hosting
/// `MainTabView`, which would need Firebase configured and a signed-in session.
/// What's being measured is the tab bar's layout of four labels, which is
/// identical either way.
@MainActor
final class TabBarLabelTests: XCTestCase {

    /// The narrowest screen the app supports. If the labels fit here they fit
    /// everywhere.
    private let narrowestWidth: CGFloat = 320

    /// `MainTabView`'s four, in order. Change one there, change it here.
    private let titles = ["Home", "Map", "Runs", "Seasons"]

    func testTabLabelsFitTheNarrowestBarAtAccessibility3() throws {
        try assertLabelsFit(at: .accessibilityExtraLarge)
    }

    /// The default size, as a control: a failure here would mean the harness is
    /// measuring the wrong thing rather than that a label is too long.
    func testTabLabelsFitAtTheDefaultTextSize() throws {
        try assertLabelsFit(at: .large)
    }

    /// The margin, stated as a number so the next label has something to be
    /// judged against. "Seasons" is the longest of the four and is the reason
    /// this file exists.
    func testSeasonsIsTheTightestLabelAndStillHasRoom() throws {
        let widths = try labelWidths(at: .accessibilityExtraLarge)
        let seasons = try XCTUnwrap(widths["Seasons"])

        XCTAssertEqual(
            widths.max(by: { $0.value < $1.value })?.key, "Seasons",
            "Some other tab label is now wider than Seasons; this file's reasoning is about the widest one."
        )
        XCTAssertLessThan(
            seasons, share * 0.8,
            "Seasons now fills more than 80% of its \(Int(share))pt slot. A fifth tab or a longer label won't fit — shorten it rather than adding minimumScaleFactor."
        )
    }

    // MARK: - Harness

    /// The width one tab gets on the narrowest screen. The bar divides evenly,
    /// so this is the real ceiling on a label — not the label's own bounds,
    /// which the bar sizes to fit whatever text it was handed.
    private var share: CGFloat { narrowestWidth / CGFloat(titles.count) }

    private func assertLabelsFit(
        at category: UIContentSizeCategory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (title, width) in try labelWidths(at: category) {
            XCTAssertLessThanOrEqual(
                width, share,
                "\"\(title)\" renders \(Int(width.rounded()))pt wide at \(category.rawValue), in a \(Int(share))pt slot.",
                file: file, line: line
            )
        }
    }

    /// Lays out a four-tab `TabView` at `category` and returns the rendered
    /// width of each label, widest copy per title.
    ///
    /// The bar lays out more than one label per title — a visible one and a
    /// mirror — so this keeps the widest of each rather than assuming one.
    private func labelWidths(at category: UIContentSizeCategory) throws -> [String: CGFloat] {
        let host = UIHostingController(
            rootView: TabView {
                ForEach(titles, id: \.self) { title in
                    Tab(title, systemImage: "circle.fill") {
                        Color.clear
                    }
                }
            }
        )

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: narrowestWidth, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()

        host.view.frame = window.bounds
        // Overridden on the hosting controller rather than the window: a
        // window's override doesn't reach a child controller's own trait
        // collection, and this one demonstrably does — the controller reports
        // the category back even though the bar then clamps it.
        host.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: category),
            forChild: host
        )
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()

        var widths: [String: CGFloat] = [:]
        for label in Self.labels(in: window) {
            guard let text = label.text, titles.contains(text) else { continue }
            let measured = (text as NSString)
                .size(withAttributes: [.font: label.font as Any])
                .width
            widths[text] = max(widths[text] ?? 0, measured)
        }

        // A hard failure rather than a skip. A skip that reports as a pass is
        // the masked-result problem this whole suite is careful about.
        XCTAssertEqual(
            widths.count, titles.count,
            "Found \(widths.count) of \(titles.count) tab labels — the bar didn't lay out, so nothing here was measured."
        )

        return widths
    }

    private static func labels(in view: UIView) -> [UILabel] {
        var found: [UILabel] = []
        if let label = view as? UILabel { found.append(label) }
        for subview in view.subviews {
            found.append(contentsOf: labels(in: subview))
        }
        return found
    }
}
