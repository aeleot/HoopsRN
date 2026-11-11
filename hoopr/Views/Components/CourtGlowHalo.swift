import SwiftUI

/// A busy court's glow, drawn behind its heat dot (UI revamp Phase 5 — the
/// definition of done's "busy courts visibly glow").
///
/// Put it in the dot's `.background`, so it takes the dot's size and never
/// moves anything: the halo swells past the dot's frame without the frame
/// growing. The curve and the Reduce Motion behaviour are `Motion.Glow`'s; the
/// map's pins draw the same curve in Core Animation (`CourtMarkerView`).
///
/// Built from `TimelineView` rather than a repeating animation so the phase is
/// read off the clock, not off when the row appeared — every glowing court on a
/// screen pulses together. Paused under Reduce Motion, where the frame doesn't
/// change anyway.
///
/// In `hooprCourtGlow`, not the dot's own colour — see there for why a glow
/// can't be the heat red.
///
/// Decorative: hidden from VoiceOver, and it never takes a touch. The row's
/// count and the dot's colour already say how busy the court is.
struct CourtGlowHalo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let frame = Motion.Glow.frame(
                at: Motion.Glow.phase(at: context.date),
                reduceMotion: reduceMotion
            )

            Circle()
                .fill(Color.hooprCourtGlow)
                .scaleEffect(frame.scale)
                .opacity(frame.opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 40) {
        ForEach(0...4, id: \.self) { count in
            Circle()
                .fill(CourtHeat.color(forGameCount: count))
                .frame(width: 10, height: 10)
                .background {
                    if CourtHeat.glows(forGameCount: count) {
                        CourtGlowHalo()
                    }
                }
        }
    }
    .padding(40)
    .background(Color.hooprBackground)
}
