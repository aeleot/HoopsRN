import SwiftUI

/// The Map band's emblem: a radar, half off the trailing edge — rings, a
/// rotating sweep and a ping that swells outward. "Near you", said as a shape.
///
/// Drawn in `hooprBrandWatermark` like Home's ball, so whatever crosses it keeps
/// the contrast `ThemeContrastTests` holds. Still under Reduce Motion.
/// Decorative: hidden from VoiceOver, and it never takes a touch.
struct MapBandRadar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweepPeriod: TimeInterval = 6
    private static let pingPeriod: TimeInterval = 3

    var body: some View {
        GeometryReader { proxy in
            let diameter = proxy.size.width * 0.62
            let center = CGPoint(x: proxy.size.width * 0.96, y: proxy.size.height * 0.4)

            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let sweep = (t / Self.sweepPeriod).truncatingRemainder(dividingBy: 1)
                let ping = (t / Self.pingPeriod).truncatingRemainder(dividingBy: 1)

                ZStack {
                    ForEach(1...4, id: \.self) { ring in
                        Circle()
                            .stroke(Color.hooprBrandWatermark, lineWidth: ring == 4 ? 3 : 2)
                            .frame(width: diameter * CGFloat(ring) / 4)
                    }

                    Circle()
                        .fill(AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.72),
                                .init(color: Color.hooprBrandWatermark, location: 1),
                            ],
                            center: .center
                        ))
                        .rotationEffect(.degrees(sweep * 360))

                    if !reduceMotion {
                        Circle()
                            .stroke(Color.hooprBrandWatermark, lineWidth: 3)
                            .scaleEffect(0.15 + 0.85 * ping)
                            .opacity(1 - ping)
                    }

                    Circle()
                        .fill(Color.hooprBrandWatermark)
                        .frame(width: diameter * 0.08)
                }
                .frame(width: diameter, height: diameter)
            }
            .position(center)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The Runs band's backdrop: a field of twinkling stars over the whole band.
///
/// In `hooprSecondaryText`, not the watermark — the orange vanishes on the
/// orange wash — and kept faint, since the band's text sits over them. Still
/// under Reduce Motion. Decorative: hidden from VoiceOver, never takes a touch.
struct RunsBandStars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// From a fixed seed, so the field doesn't reshuffle on every redraw:
    /// position as a fraction of the band, size in points, twinkle phase and
    /// speed.
    private static let stars: [(x: Double, y: Double, size: Double, phase: Double, speed: Double)] = {
        var seed: UInt64 = 0x5EED_600D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<60).map { _ in
            (next(), next(), 1.5 + 3 * next() * next(), next() * 2 * .pi, 0.8 + 1.6 * next())
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for star in Self.stars {
                    let twinkle = reduceMotion ? 0.35 : 0.1 + 0.45 * (0.5 + 0.5 * sin(t * star.speed + star.phase))
                    let rect = CGRect(x: star.x * size.width - star.size / 2, y: star.y * size.height - star.size / 2,
                                      width: star.size, height: star.size)
                    canvas.fill(Path(ellipseIn: rect), with: .color(Color.hooprSecondaryText.opacity(twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 0) {
        ZStack {
            HeroWash(placement: .leading(.hooprBrandWash))
            MapBandRadar()
        }
        .frame(height: 220)
        .clipped()

        ZStack {
            HeroWash(placement: .leading(.hooprBrandWash))
            RunsBandStars()
        }
        .frame(height: 220)
        .clipped()
    }
}
