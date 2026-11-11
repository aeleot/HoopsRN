import SwiftUI

/// The app's spacing vocabulary, written down once.
///
/// **The scale was already there; it just wasn't named.** Phase 0 of the UI
/// revamp counted 231 numeric `.padding(…)` literals in `Views/`, and four
/// values — 8, 12, 16, 20 — carried 145 of them. That is a real scale being
/// re-typed at every call site, and re-typing is how the Runs tab came to inset
/// its title 20pt and its cards 16: nothing said which number "the page margin"
/// was, so two people each picked one.
///
/// Two layers, and the second is the one views should reach for:
///
/// - **The scale** (`xs` … `xxxl`) — the steps themselves, on a 4pt grid with a
///   2pt hairline below it.
/// - **The roles** (`pageMargin`, `cardPadding`, …) — what a step is *for*. A
///   view that says `Spacing.pageMargin` is saying which job the number does,
///   so retuning the page margin later moves every screen together instead of
///   being a search for the right 20s.
///
/// **Fixed, not scaled.** These are points, not `@ScaledMetric`. The app's rule
/// for text is that it reflows and never shrinks (`Typography.swift`); the
/// space around text is deliberately not the thing that grows with it, or a
/// reader at `.accessibility3` loses a third of the width to margins.
///
/// **What this does not cover.** Corner radii (four in real use — 10, 12, 14,
/// 16 — with no rule about which is which), fixed control heights (seven button
/// heights for what is three kinds of button) and the `ProfileView` row gap of
/// 10 are all off this scale on purpose and stay as they are: they are
/// composition decisions.
enum Spacing {

    // MARK: - The scale

    /// The gap inside a tight cluster — a glyph and its caption.
    static let hairline: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Every step, in order. Exposed so a test can ask whether a role is
    /// actually *on* the scale rather than a number that happens to look like
    /// one.
    static let scale: [CGFloat] = [hairline, xs, sm, md, lg, xl, xxl, xxxl]

    // MARK: - Roles

    /// The inset between the screen's edge and its content — on every tab, every
    /// pushed screen and every sheet's body. Home, Seasons, the profile and the
    /// map's court card already used 20; the Runs tab used 16 for its cards under
    /// a title inset 20, and now uses this too.
    static let pageMargin = xl

    /// The padding inside a card, between its edge and its content.
    static let cardPadding = lg

    /// The gap between the distinct cards of one screen's stack — squad home,
    /// game day, the result screen.
    static let interCard = lg

    /// The gap between the repeated rows or cards of one list — the runs under
    /// a section header.
    static let interRow = md

    /// The gap between a screen's sections, where each is a block of its own
    /// rather than a card in a stack — Home.
    static let section = xxl

    /// A small filled capsule that names something — a run's HOSTING / WAITLIST
    /// / FULL badge. Deliberately generous horizontally: the label is 11pt bold
    /// caps and reads as a word, not a number.
    enum Pill {
        static let horizontal = sm
        static let vertical = xs
    }

    /// A filter chip floating over the map on glass.
    ///
    /// **Off the scale on purpose.** 14 × 9 is optically tuned against the
    /// 13pt label — it gives a capsule about 34pt tall, which is what reads as
    /// a chip rather than a button — and rounding it to 16 × 8 changes that
    /// silhouette. It is named here so it is one decision rather than a pair
    /// of literals, not because it is a step.
    enum Chip {
        static let horizontal: CGFloat = 14
        static let vertical: CGFloat = 9
    }
}
