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

/// Resolves the scaled size against the environment's Dynamic Type setting.
///
/// A `ViewModifier` rather than a `Font`-returning helper because the scale
/// factor is environment-dependent: reading `@Environment(\.dynamicTypeSize)`
/// is what makes SwiftUI re-evaluate this when the reader changes their text
/// size while the app is open.
private struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let maximumSize: CGFloat?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight))
    }

    private var scaledSize: CGFloat {
        // Passed explicitly rather than relying on `UITraitCollection.current`,
        // which is only correct inside a UIKit update cycle — this modifier
        // also runs from previews and from tests.
        let traits = UITraitCollection(
            preferredContentSizeCategory: Self.contentSizeCategory(for: dynamicTypeSize)
        )
        let scaled = UIFontMetrics(forTextStyle: Self.metricsStyle(for: size))
            .scaledValue(for: size, compatibleWith: traits)

        guard let maximumSize else { return scaled }
        return min(scaled, maximumSize)
    }

    /// The text style whose default size is nearest `size`, so the scaling
    /// curve matches what the system would apply to text of that size. Body and
    /// large sizes are deliberately scaled less aggressively by the metrics
    /// tables than captions are; borrowing the wrong style would undo that.
    private static func metricsStyle(for size: CGFloat) -> UIFont.TextStyle {
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
    private static func contentSizeCategory(
        for size: DynamicTypeSize
    ) -> UIContentSizeCategory {
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
