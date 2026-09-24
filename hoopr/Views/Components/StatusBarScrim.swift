import SwiftUI

extension View {
    /// Keeps scrolled content out from under the clock and the battery
    /// (UI revamp Phase 4 — where the brief's M2 said the band's scroll edge
    /// would land).
    ///
    /// **The problem it answers, seen on the device (2026-09-23).** Home,
    /// Runs and the Seasons screens have no bar: the band *is* the header,
    /// and it scrolls. Once it had, the band's label and the profile button
    /// sat directly under the status bar's text. iOS 26 draws a scroll edge
    /// effect only behind real bar content — an empty `safeAreaBar` with
    /// `scrollEdgeEffectStyle(.soft)` was tried and drew nothing — so this is
    /// the status bar's own strip in the page colour, solid behind the
    /// clock and fading out over the strip's lower quarter.
    ///
    /// **At rest it is invisible**: the band starts below the status bar, so
    /// the strip was already the page. It only shows once something scrolls
    /// up into it. Not glass: under the status bar there's nothing to read
    /// through, only text to keep clear.
    func hooprStatusBarScrim() -> some View {
        overlay {
            // The strip runs from the top of the screen down to where this
            // view begins, which is the top of its safe area — measured on
            // the device at 62pt on iPhone 17. Taken from the view's global
            // position because the obvious alternatives weren't the strip:
            // a zero-high view extended into the safe area covered 20pt of it,
            // this reader's own `safeAreaInsets.top` reports the same 62pt a
            // second time (so adding the two hid the band's label at rest),
            // and a reader that ignores the safe area reports none.
            GeometryReader { proxy in
                let strip = max(0, proxy.frame(in: .global).minY)
                LinearGradient(
                    stops: [
                        .init(color: Color.hooprBackground, location: 0),
                        .init(color: Color.hooprBackground, location: 0.75),
                        .init(color: Color.hooprBackground.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: strip)
                .offset(y: -strip)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
