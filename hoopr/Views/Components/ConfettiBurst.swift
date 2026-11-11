import SwiftUI

/// Confetti falling from the top of the screen, once, for a confirmed win (UI
/// revamp Phase 5 — "match wins celebrate").
///
/// **Built-in, not a package.** Phase 5 listed `ConfettiSwiftUI`; this is
/// `Canvas` and `TimelineView` over a pure particle model (`Confetti`), which is
/// about a hundred lines and leaves nothing to maintain. The reasons are in
/// `BUILD_AND_CONFIG.md` § Dependencies.
///
/// It may not get in the way, and by construction it can't:
///
/// - **It never takes a touch** — the screen under it is fully usable while it
///   falls, so it needs no "skip": there is nothing to skip past.
/// - **It never carries information.** "You won" and the winner's crest say
///   it; this is hidden from VoiceOver.
/// - **Under Reduce Motion it draws nothing** and finishes at once.
/// - **It ends by itself** after `Confetti.duration`, and calls `onFinished`
///   so the owner can drop it.
///
/// Whether to fire at all — once per win, never on a re-render — is the
/// owner's decision (`ResultViewModel.shouldCelebrate`), not this view's.
struct ConfettiBurst: View {
    /// Theme roles only. A piece takes `colors[index % count]`, so repeating a
    /// colour weights it.
    let colors: [Color]
    let onFinished: () -> Void

    private let pieces: [Confetti.Piece]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    init(colors: [Color], seed: UInt64, onFinished: @escaping () -> Void) {
        self.colors = colors
        self.onFinished = onFinished
        self.pieces = Confetti.pieces(count: Confetti.count, seed: seed)
    }

    var body: some View {
        Group {
            if reduceMotion || colors.isEmpty {
                Color.clear
            } else {
                TimelineView(.animation) { context in
                    Canvas { graphics, size in
                        guard let start else { return }
                        let elapsed = context.date.timeIntervalSince(start)
                        for piece in pieces {
                            draw(piece, at: elapsed, in: size, into: graphics)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start = Date() }
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Confetti.duration))
            }
            onFinished()
        }
    }

    private func draw(_ piece: Confetti.Piece, at elapsed: TimeInterval, in size: CGSize, into graphics: GraphicsContext) {
        guard let frame = Confetti.frame(of: piece, at: elapsed, in: size) else { return }

        var context = graphics
        context.opacity = frame.opacity
        context.translateBy(x: frame.position.x, y: frame.position.y)
        context.rotate(by: .radians(frame.angle))
        // The flutter: a piece turning edge-on narrows to a sliver and back.
        context.scaleBy(x: frame.flip, y: 1)

        let rect = CGRect(
            x: -piece.width / 2,
            y: -piece.height / 2,
            width: piece.width,
            height: piece.height
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: 1),
            with: .color(colors[piece.colorIndex % colors.count])
        )
    }
}

/// The particle model behind `ConfettiBurst`: where each piece is, at any
/// moment, as a pure function of a seed and the time — so it can be tested
/// without drawing anything, and the same seed always falls the same way.
nonisolated enum Confetti {
    /// How long a burst lasts, from the first piece entering to the last one
    /// fading out.
    static let duration: TimeInterval = 2.6
    /// The last stretch of `duration`, over which every piece fades to nothing
    /// — so none is cut off mid-air.
    static let fadeOut: TimeInterval = 0.7
    static let count = 70
    /// Points per second squared. Low, because paper falls through air rather
    /// than dropping: a piece should drift past the band, not streak through.
    static let gravity: CGFloat = 180

    /// Enough colour slots that a palette of up to eight is used evenly.
    static let colorSlots = 8

    struct Piece: Equatable {
        /// Start, across the width, as a fraction of it.
        let x0: CGFloat
        /// Start, in points above the top edge — negative, so nothing appears
        /// in mid-air.
        let y0: CGFloat
        let vx: CGFloat
        let vy: CGFloat
        let sway: CGFloat
        let swayRate: Double
        let phase: Double
        let angle0: Double
        let spin: Double
        let flipRate: Double
        let width: CGFloat
        let height: CGFloat
        let colorIndex: Int
    }

    struct Frame: Equatable {
        let position: CGPoint
        let angle: Double
        /// The horizontal scale that makes a piece flutter, never quite zero.
        let flip: CGFloat
        let opacity: Double
    }

    static func pieces(count: Int, seed: UInt64) -> [Piece] {
        var random = SeededRandom(seed: seed)
        return (0..<max(count, 0)).map { _ in
            Piece(
                x0: CGFloat.random(in: 0...1, using: &random),
                y0: CGFloat.random(in: -44 ... -12, using: &random),
                vx: CGFloat.random(in: -40...40, using: &random),
                vy: CGFloat.random(in: 60...160, using: &random),
                sway: CGFloat.random(in: 6...20, using: &random),
                swayRate: Double.random(in: 3...6, using: &random),
                phase: Double.random(in: 0...(2 * .pi), using: &random),
                angle0: Double.random(in: 0...(2 * .pi), using: &random),
                spin: Double.random(in: -6...6, using: &random),
                flipRate: Double.random(in: 5...10, using: &random),
                width: CGFloat.random(in: 6...10, using: &random),
                height: CGFloat.random(in: 3...5, using: &random),
                colorIndex: Int.random(in: 0..<colorSlots, using: &random)
            )
        }
    }

    /// Where `piece` is `elapsed` seconds into the burst, or `nil` before it
    /// starts and once it's over.
    static func frame(of piece: Piece, at elapsed: TimeInterval, in size: CGSize) -> Frame? {
        guard elapsed >= 0, elapsed < duration else { return nil }

        let t = CGFloat(elapsed)
        let x = piece.x0 * size.width
            + piece.vx * t
            + piece.sway * CGFloat(sin(piece.swayRate * elapsed + piece.phase))
        let y = piece.y0 + piece.vy * t + 0.5 * gravity * t * t

        let fadeStart = duration - fadeOut
        let opacity = elapsed < fadeStart ? 1 : max(0, (duration - elapsed) / fadeOut)

        let turn = CGFloat(cos(piece.flipRate * elapsed + piece.phase))
        let flip = turn < 0 ? min(turn, -0.1) : max(turn, 0.1)

        return Frame(
            position: CGPoint(x: x, y: y),
            angle: piece.angle0 + piece.spin * elapsed,
            flip: flip,
            opacity: opacity
        )
    }

    /// A stable seed for a string — a game's ID — so one win always falls the
    /// same way. FNV-1a, because `hashValue` changes between launches.
    static func seed(for string: String) -> UInt64 {
        string.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }

    /// SplitMix64: small, fast, and the same sequence for the same seed, which
    /// `SystemRandomNumberGenerator` can't promise.
    struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

#Preview {
    ConfettiBurst(
        colors: [.hooprSquad("red"), .hooprSquad("red"), .hooprOrange, .hooprSquad("gold")],
        seed: 42,
        onFinished: {}
    )
    .background(Color.hooprBackground)
}
