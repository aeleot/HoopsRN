import CoreGraphics
import Foundation

/// How far up the sheet is resting. `medium` is the default: enough list to be
/// useful, enough map to stay oriented.
///
/// File scope rather than nested in `MapTab`, and `nonisolated`, so the
/// geometry below can be pure — and so the detent machine can finally be
/// tested. It was the densest interaction code in the app with no coverage at
/// all.
nonisolated enum SheetDetent: Equatable, CaseIterable {
    case collapsed
    case medium
    case expanded
}

/// The sheet is always in exactly one of these. `.detail` carries the detent to
/// fall back to, so dismissing a court restores whatever the sheet was showing
/// beforehand.
nonisolated enum SheetState: Equatable {
    case rest(SheetDetent)
    case detail(court: Court, returningTo: SheetDetent)

    var detent: SheetDetent {
        switch self {
        case .rest(let detent):           return detent
        case .detail(_, let returningTo): return returningTo
        }
    }

    /// Where the sheet actually renders right now.
    ///
    /// A card must never render **collapsed** — that's the bug this exists for:
    /// a court tapped while the list sits collapsed would inherit that offset
    /// and draw entirely off-screen. Everything else keeps its height, so
    /// tapping a court from a full-height list doesn't shrink the sheet out
    /// from under your thumb.
    var displayDetent: SheetDetent {
        switch self {
        case .rest(let detent):
            return detent
        case .detail(_, let returningTo):
            return returningTo == .collapsed ? .medium : returningTo
        }
    }

    var selectedCourt: Court? {
        if case .detail(let court, _) = self { return court }
        return nil
    }
}

/// The sheet's detent arithmetic, extracted from the view.
///
/// `MapTab` owns the gestures, the animation and the state; this owns only
/// where the sheet sits given a detent and a finger position. Pure and
/// `nonisolated` — the same move `SheetMetrics` above already made, and what
/// lets `MapTabDetentTests` pin behaviour that used to be reachable only
/// through a live drag.
nonisolated struct SheetGeometry: Equatable {
    /// The tab's own height *minus* the tab bar. Every detent is a fraction of
    /// it. See `MapTab.tabBarInset` for why the subtraction is load-bearing.
    let containerHeight: CGFloat

    /// Finger travel past which a drag settles to the next detent.
    static let detentThreshold: CGFloat = 60

    /// How far the sheet may be dragged beyond its limits, easing toward this
    /// rather than tracking the finger 1:1.
    static let rubberBandLimit: CGFloat = 40

    var mediumHeight: CGFloat { containerHeight / 3 }
    var expandedHeight: CGFloat { containerHeight * 0.78 }

    func baseHeight(for detent: SheetDetent) -> CGFloat {
        switch detent {
        case .collapsed, .medium: return mediumHeight
        case .expanded:           return expandedHeight
        }
    }

    /// The sheet grows and shrinks between medium and expanded as you drag, so
    /// its top edge tracks your finger instead of the whole panel sliding.
    func sheetHeight(detent: SheetDetent, drag: CGFloat) -> CGFloat {
        let base = baseHeight(for: detent)
        return min(max(base - drag, mediumHeight), expandedHeight)
    }

    /// Only non-zero heading to or from `.collapsed`, where the sheet leaves the
    /// screen entirely rather than shrinking below its medium height.
    func sheetOffset(detent: SheetDetent, drag: CGFloat) -> CGFloat {
        let base: CGFloat = detent == .collapsed ? mediumHeight : 0
        let travel: CGFloat = detent == .collapsed
            ? drag
            : max(0, drag - (baseHeight(for: detent) - mediumHeight))
        return rubberBanded(base + travel)
    }

    /// Keeps the sheet inside its travel range while still following the
    /// finger, so it can be neither flung off-screen nor dragged above its full
    /// height.
    func rubberBanded(_ offset: CGFloat) -> CGFloat {
        if offset < 0 {
            return -Self.resistance(-offset)
        }
        if offset > mediumHeight {
            return mediumHeight + Self.resistance(offset - mediumHeight)
        }
        return offset
    }

    /// Overshoot that eases towards a hard limit instead of tracking 1:1.
    static func resistance(_ overshoot: CGFloat) -> CGFloat {
        rubberBandLimit * (1 - exp(-overshoot / rubberBandLimit))
    }

    /// One detent per gesture, so a hard fling can't skip from expanded
    /// straight off the bottom of the screen.
    static func nextDetent(from detent: SheetDetent, projecting travel: CGFloat) -> SheetDetent {
        switch detent {
        case .expanded:
            return travel > detentThreshold ? .medium : .expanded
        case .medium:
            if travel > detentThreshold { return .collapsed }
            if travel < -detentThreshold { return .expanded }
            return .medium
        case .collapsed:
            return travel < -detentThreshold ? .medium : .collapsed
        }
    }
}
