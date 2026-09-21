import SwiftUI

/// Liquid Glass where the OS has it, a material where it doesn't.
///
/// `glassEffect(_:in:)` is iOS 26. The app's floor is **iOS 18** — see
/// `BUILD_AND_CONFIG.md` — so every glass surface in the app goes through here
/// rather than calling the API directly. One `#available` instead of five, and
/// one place to retune the fallback when it turns out to be wrong on a device.
///
/// **The fallback is a material, not a flat fill.** Every surface that asks for
/// glass here floats over something moving — the map, a scrolling list — so it
/// has to stay translucent to read as the same object. An opaque fill turns a
/// floating chip into a panel, which is the exact failure `GlassChip` documents
/// for its selected state.
///
/// **No hairline on the fallback.** `HooprSearchField` explains the rule: glass
/// carries its own edge, so a stroke on top of it reads as a seam. A material
/// carries enough of one that adding a second is the same mistake one layer
/// down — and the header bar in `ProfileIdentity` extends past the top safe
/// area, where any stroke would draw a box around the status bar.
extension View {
    /// - Parameters:
    ///   - tint: Colours the glass. `nil` leaves it untinted.
    ///   - interactive: Whether the surface reacts to touch. False for
    ///     chrome that isn't a control — a header bar, not a button.
    ///   - shape: The shape the effect is drawn in.
    func hooprGlass<S: Shape>(
        tint: Color? = nil,
        interactive: Bool = true,
        in shape: S
    ) -> some View {
        modifier(HooprGlass(tint: tint, interactive: interactive, shape: shape))
    }
}

private struct HooprGlass<S: Shape>: ViewModifier {
    let tint: Color?
    let interactive: Bool
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background { fallback }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return interactive ? glass.interactive() : glass
    }

    /// The tint rides *on top of* the material rather than replacing it, so a
    /// tinted surface stays the same translucent object with colour in it —
    /// the behaviour `GlassChip` depends on for its selected state.
    ///
    /// `0.55` is the opacity at which `hooprOnBrand` (black) still clears AA on
    /// the result over a light map. Solid brand orange would clear it more
    /// easily but reads as the opaque swap this is avoiding.
    @ViewBuilder
    private var fallback: some View {
        if let tint {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(tint.opacity(0.55)) }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
