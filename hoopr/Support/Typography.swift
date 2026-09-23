import SwiftUI
import UIKit

/// Dynamic Type for a design drawn in fixed point sizes.
///
/// The app's type scale was specified as literal sizes — 13pt captions, 28pt
/// greeting — and `Font.system(size:)` pins those, ignoring the reader's text
/// size entirely. Swapping every call site to a semantic style (`.footnote`,
/// `.title`) would scale correctly but silently redraw the whole app at
/// different sizes, since the style defaults don't line up with the sizes the
/// design chose.
///
/// So: keep the size, scale it. `UIFontMetrics` applies the same curve the
/// system applies to its own text styles, anchored to whichever style's default
/// size is nearest — a 13pt label scales the way `.footnote` does, a 28pt one
/// the way `.title` does. At the default text size the result is the literal
/// size the design asked for, so nothing moves for a reader who hasn't changed
/// the setting.
///
/// Use `.hooprFont(_:weight:)` in place of `.font(.system(size:weight:))`.
/// Symbols locked inside a fixed-size frame keep `.font(.system(size:))` — see
/// `maximumSize` for the cases in between.
extension View {
    /// A system font of `size`, scaled for the reader's Dynamic Type setting.
    ///
    /// - Parameters:
    ///   - size: The point size at the default text size (`.large`).
    ///   - weight: Font weight, as with `Font.system(size:weight:)`.
    ///   - maximumSize: Ceiling on the scaled size, for text inside a frame
    ///     that can't grow — a fixed-height tab strip, a badge sized to its
    ///     capsule. Omit it wherever the layout can reflow, which is most
    ///     places: a cap is a clipped word at the accessibility sizes, and is
    ///     only the lesser evil when the alternative is a broken frame.
    func hooprFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        maximumSize: CGFloat? = nil
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, maximumSize: maximumSize))
    }
}

/// The size arithmetic behind `hooprFont`, as pure functions.
///
/// Pulled out of the modifier below so the one question the type ramp can get
/// wrong — *does this still fit the frame it's locked into?* — can be asked in a
/// test without hosting a view. `SeasonsAccessibilityTests` asks it of every
/// fixed-size badge in the app; the answer is only trustworthy because this is
/// the same code the modifier runs, rather than a second copy of the curve.
nonisolated enum HooprFontMetrics {
    /// The point size `hooprFont(size, maximumSize:)` resolves to at `category`.
    static func scaledSize(
        _ size: CGFloat,
        maximumSize: CGFloat? = nil,
        at category: UIContentSizeCategory
    ) -> CGFloat {
        // Passed explicitly rather than relying on `UITraitCollection.current`,
        // which is only correct inside a UIKit update cycle — this also runs
        // from previews and from tests.
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let scaled = UIFontMetrics(forTextStyle: metricsStyle(for: size))
            .scaledValue(for: size, compatibleWith: traits)

        guard let maximumSize else { return scaled }
        return min(scaled, maximumSize)
    }

    /// The text style whose default size is nearest `size`, so the scaling
    /// curve matches what the system would apply to text of that size. Body and
    /// large sizes are deliberately scaled less aggressively by the metrics
    /// tables than captions are; borrowing the wrong style would undo that.
    static func metricsStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11.5:   return .caption2     // 11
        case ..<12.5:   return .caption1     // 12
        case ..<14:     return .footnote     // 13
        case ..<15.5:   return .subheadline  // 15
        case ..<16.5:   return .callout      // 16
        case ..<18.5:   return .body         // 17
        case ..<21:     return .title3       // 20
        case ..<25:     return .title2       // 22
        case ..<31:     return .title1       // 28
        default:        return .largeTitle   // 34
        }
    }

    /// SwiftUI's `DynamicTypeSize` doesn't bridge to `UIContentSizeCategory`
    /// with a documented initialiser, so the mapping is written out. It's the
    /// same eleven-step ladder in both types, accessibility sizes included.
    static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall:                 return .extraSmall
        case .small:                  return .small
        case .medium:                 return .medium
        case .large:                  return .large
        case .xLarge:                 return .extraLarge
        case .xxLarge:                return .extraExtraLarge
        case .xxxLarge:               return .extraExtraExtraLarge
        case .accessibility1:         return .accessibilityMedium
        case .accessibility2:         return .accessibilityLarge
        case .accessibility3:         return .accessibilityExtraLarge
        case .accessibility4:         return .accessibilityExtraExtraLarge
        case .accessibility5:         return .accessibilityExtraExtraExtraLarge
        @unknown default:             return .large
        }
    }
}

/// Resolves the scaled size against the environment's Dynamic Type setting.
///
/// A `ViewModifier` rather than a `Font`-returning helper because the scale
/// factor is environment-dependent: reading `@Environment(\.dynamicTypeSize)`
/// is what makes SwiftUI re-evaluate this when the reader changes their text
/// size while the app is open. The arithmetic itself lives in
/// `HooprFontMetrics`, so it can be tested without a view.
private struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let maximumSize: CGFloat?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight))
    }

    private var scaledSize: CGFloat {
        HooprFontMetrics.scaledSize(
            size,
            maximumSize: maximumSize,
            at: HooprFontMetrics.contentSizeCategory(for: dynamicTypeSize)
        )
    }
}

// MARK: - Type roles

/// What a size is *for*, written down once.
///
/// `hooprFont` fixed the scaling problem — a literal size that still respects
/// Dynamic Type — but left every call site choosing its own number, so the app
/// grew six spellings of the same uppercase section label at two sizes and two
/// weights (`context/plans/UI_REVAMP_AUDIT.md` §2.4). These roles are the
/// vocabulary above the numbers: a view says what a piece of text *is*, and
/// this file decides how big that is.
///
/// **Constraint 2 still holds.** Every role resolves to a `hooprFont` call, so
/// there is one scaling curve in the app and `HooprFontMetrics` stays the only
/// arithmetic. A call site that needs a size this table doesn't have keeps
/// using `.hooprFont` directly — the roles are a vocabulary, not a lock.
///
/// **The display tier is not capped, and that is deliberate.** `numeral` and
/// `display` reflow; a cap is a clipped word at the accessibility sizes, and
/// the hero is the one place in the app where a clipped word would take the
/// screen's whole answer with it. What guards them instead is a metrics type
/// per hero (`HomeHeroMetrics`), measured against the frame it lives in — the
/// pattern `ResultPillMetrics` established.
///
/// **What the ladder does at `.accessibility3`, measured** (the values
/// `HooprFontMetrics` produces on iOS 26.5, not an estimate):
///
/// | role | default | AX3 | × |
/// |---|---|---|---|
/// | `numeral` | 44 | 65.3 | 1.49 |
/// | `display` | 40 | 59.7 | 1.49 |
/// | `title` | 28 | 47.0 | 1.68 |
/// | `caption` | 13 | 29.0 | 2.23 |
///
/// The *smallest* roles grow most, so the hero-to-caption ratio falls from
/// 3.4× to 2.3× — **a third of the hierarchy scales away**. That is why the
/// redesign carries rank with layers and position (the hero band) rather than
/// with point size alone: at `.accessibility3` the hero is still the hero
/// because of where it sits.
nonisolated enum HooprTextRole: CaseIterable {
    /// The one number a screen exists to deliver: time to tip-off, spots left,
    /// a W–L record. Tabular, so a counting number doesn't jitter its own
    /// layout as it changes.
    case numeral
    /// The one *phrase* a screen exists to deliver, where the answer is words
    /// rather than a number — a court name, an outcome.
    case display
    /// A screen or squad's name, where that name is information rather than a
    /// restatement of the tab it sits on.
    case title
    /// The subject of a block within a screen.
    case headline
    /// A list row's primary line.
    case subhead
    /// Supporting sentences.
    case body
    /// Secondary metadata — the quiet line under a row.
    case caption
    /// The uppercase section label. **One spelling**, replacing the six the
    /// audit found.
    case label
    /// Text inside a fixed capsule — HOSTING, WAITLIST, FULL.
    case badge

    var size: CGFloat {
        switch self {
        case .numeral:  return 44
        case .display:  return 40
        case .title:    return 28
        case .headline: return 20
        case .subhead:  return 17
        case .body:     return 15
        case .caption:  return 13
        case .label:    return 12
        case .badge:    return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .numeral, .display, .title, .label, .badge: return .bold
        case .headline, .subhead:                        return .semibold
        case .body, .caption:                            return .regular
        }
    }

    /// Only the two uppercase roles cap, and only because they live inside
    /// capsules and header rows that can't grow. Everything else reflows.
    var maximumSize: CGFloat? {
        switch self {
        case .label: return 16
        case .badge: return 14
        default:     return nil
        }
    }

    /// The same weight as `weight`, in UIKit's spelling.
    ///
    /// `Font.Weight` carries no way to read its value back out, so a metrics
    /// type that wants to *measure* text in this role — rather than draw it —
    /// has nothing to hand `UIFont`. This is that bridge, and it is written as
    /// a switch over the same cases so the two can't drift: a role whose
    /// `weight` changes without this changing is a measurement that no longer
    /// describes what the screen draws.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .numeral, .display, .title, .label, .badge: return .bold
        case .headline, .subhead:                        return .semibold
        case .body, .caption:                            return .regular
        }
    }

    /// Fixed-width digits. Only the numeral tier: applying it to body text
    /// would change how every sentence in the app renders.
    var usesTabularFigures: Bool { self == .numeral }

    /// Uppercased through `textCase`, not by uppercasing the string, so the
    /// accessibility label keeps its natural casing and VoiceOver doesn't
    /// spell the word out letter by letter.
    var isUppercase: Bool { self == .label || self == .badge }

    var kerning: CGFloat {
        switch self {
        case .label: return 0.6
        case .badge: return 0.4
        default:     return 0
        }
    }
}

extension View {
    /// Applies a type role. See `HooprTextRole`.
    func hooprType(_ role: HooprTextRole) -> some View {
        modifier(HooprTypeRole(role: role))
    }
}

private struct HooprTypeRole: ViewModifier {
    let role: HooprTextRole

    @ViewBuilder
    func body(content: Content) -> some View {
        let sized = content.hooprFont(role.size, weight: role.weight, maximumSize: role.maximumSize)

        if role.usesTabularFigures {
            sized.monospacedDigit()
        } else if role.isUppercase {
            sized.textCase(.uppercase).kerning(role.kerning)
        } else {
            sized
        }
    }
}
