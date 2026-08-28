import SwiftUI

extension View {
    /// The app's card recipe — surface, hairline, soft lift.
    ///
    /// This lived as a `private extension` inside `HomeTab`, whose own note
    /// said the other hand-rolled copies were "left alone deliberately: folding
    /// them in is a refactor with its own diff, not something to smuggle into a
    /// new screen." This is that diff. The map redesign needed the recipe in
    /// two more places, and a fifth copy is well past where a design system
    /// starts drifting.
    ///
    /// The values are `GameCard`'s, which every other copy already matched:
    /// `hooprSurface`, a 6%-opacity shadow at radius 8, and a 1pt
    /// `hooprBorder` stroke. In light mode the surface equals the page, so the
    /// separation is carried entirely by that hairline and a very soft lift; in
    /// dark mode the surface rises off pure black and `hooprShadow` quadruples
    /// the opacity to compensate.
    func cardChrome(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.hooprBorder, lineWidth: 1)
        )
    }
}
