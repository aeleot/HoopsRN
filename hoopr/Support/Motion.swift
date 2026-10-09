import SwiftUI
import UIKit

/// The app's motion vocabulary (UI revamp Phase 3).
///
/// Before this, motion was written where it happened: about thirty call sites,
/// each with its own `.easeInOut(duration:)` or spring, and none of them asking
/// whether the reader had turned on Reduce Motion. Now a change says **what
/// kind of change it is** and this file decides how that moves:
///
/// - **`move`** — something the user moved: a selection sliding under its
///   label, a panel opening, the map's sheet settling on a detent. A spring,
///   damped enough that a control never visibly overshoots.
/// - **`snap`** — a control's own state: a radio, a chip, a stepper's count, a
///   button being pressed. Faster and firmer than `move`.
/// - **`swap`** — content arriving in place of other content: the matchmaking
///   card's state, a sheet's next step. Softer, because the eye has to re-read.
///
/// **Reduce Motion replaces every one with a short cross-fade** (`reduced`),
/// and entrances stop travelling (`hooprLift` becomes a plain fade). Springs are
/// frame-rate independent, so the same values are right at 60 and 120Hz.
///
/// **Nothing animates on first appearance.** Every animation here is attached
/// to a *change* — `withAnimation` in an action, `.animation(_:value:)` on a
/// value, a transition on an insertion — so a screen draws in its final state
/// the first time. A view that wants motion on appearance is doing something
/// this vocabulary deliberately doesn't offer.
///
/// **One exception, and it isn't a change: a busy court's glow** (`Glow`,
/// Phase 5). It is an ambient indicator — "this court is live today", the way
/// a recording light is on — so it runs for as long as it's on screen. It is
/// bounded three ways: only courts over `CourtHeat.glowsFrom` have it, it is
/// drawn behind the heat dot and never moves layout, and under Reduce Motion it
/// holds still. It never carries information alone: the count and the heat
/// colour say the same thing.
///
/// **And a second, which isn't either: the empty-state map's drift** (`Drift`,
/// Home's "Tonight nearby" preview). The map behind "Nothing on nearby yet"
/// wanders a few points on a slow loop and its dots ping on `Glow`'s clock, so
/// an empty answer still reads as a live place. Bounded the same three ways:
/// only on that one decorative map, it moves no layout (the map is drawn
/// oversize and slid inside its clip), and under Reduce Motion it is a still
/// frame.
///
/// **And a third, which is a change on a clock: the stats scoreboard**
/// (`Scoreboard`, Home). Its panels take turns, one sliding across as the next
/// arrives every `Scoreboard.dwell` seconds. Each slide is an ordinary
/// animated change, so the screen still draws in its final state first; what
/// is new is that a timer makes the change. Bounded harder than the others,
/// because it moves text: a visible pause control (WCAG 2.2.2), nothing at all
/// under Reduce Motion or VoiceOver (every panel shown at once instead), and
/// no timer while it is scrolled away or the app is in the background.
///
/// The static `Animation` and `AnyTransition` members read
/// `UIAccessibility.isReduceMotionEnabled`, the setting SwiftUI's
/// `accessibilityReduceMotion` mirrors, so an action closure — which has no
/// environment — still honours it. The pure functions take the flag as an
/// argument; they are what `MotionTests` pins.
enum Motion {
    enum Kind {
        case move
        case snap
        case swap
    }

    enum Duration {
        /// The cross-fade every kind becomes under Reduce Motion: long enough to
        /// read as a change, short enough not to feel like a delay.
        static let reduced: TimeInterval = 0.15
        /// How long an entrance takes to arrive.
        static let enter: TimeInterval = 0.28
        /// How long an exit takes to leave — quicker than an entrance, so what's
        /// going gets out of the way of what's coming.
        static let exit: TimeInterval = 0.16
        /// The whole window cross-fading from one palette to the other when the
        /// appearance preference changes (`WindowAppearance`). Already a fade,
        /// so Reduce Motion leaves it as it is.
        static let appearance: TimeInterval = 0.3
    }

    /// How far an entrance travels before it settles, in points.
    static let liftDistance: CGFloat = 8

    /// A card crossing a scroll view's edge (`hooprScrollLift`).
    static let scrollEdgeOpacity: Double = 0.6
    static let scrollEdgeScale: CGFloat = 0.96

    /// A pressed button's scale and opacity (`HooprPressStyle`).
    static let pressedScale: CGFloat = 0.97
    static let pressedOpacity: Double = 0.85

    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: Duration.reduced)
        }
        switch kind {
        case .move: return .spring(response: 0.35, dampingFraction: 0.85)
        case .snap: return .spring(response: 0.25, dampingFraction: 0.9)
        case .swap: return .spring(response: 0.4, dampingFraction: 0.9)
        }
    }

    /// Content arriving: it lifts `liftDistance` into place as it fades in,
    /// over `Duration.enter`; what it replaces fades out over `Duration.exit`.
    /// Under Reduce Motion, both are a plain `reduced` fade.
    static func lift(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: Duration.reduced))
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: liftDistance))
                .animation(.easeOut(duration: Duration.enter)),
            removal: .opacity
                .animation(.easeIn(duration: Duration.exit))
        )
    }

    /// Something small appearing on top of something else — a badge on the
    /// inbox: it grows out of its own centre as it fades in. Under Reduce
    /// Motion, a fade.
    static func pop(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity.animation(.easeInOut(duration: Duration.reduced))
            : .scale(scale: 0.5).combined(with: .opacity).animation(animation(.snap, reduceMotion: false))
    }

    /// A card presented over the page — the run calendar's month: it settles
    /// from a little smaller as it fades in, and fades as it goes. Under Reduce
    /// Motion, a fade.
    static func present(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity.animation(.easeInOut(duration: Duration.reduced))
            : .scale(scale: presentedScale).combined(with: .opacity).animation(animation(.snap, reduceMotion: false))
    }

    /// How much smaller a presented card starts: enough to read as arriving,
    /// little enough that it doesn't read as a badge popping.
    static let presentedScale: CGFloat = 0.94

    /// Whether a pressed button shrinks, or only dims.
    static func pressScales(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Whether a count changing from `old` to `new` bounces its symbol: only
    /// when it rises — something new has arrived — and never under Reduce
    /// Motion. A count falling is the user dealing with it, which needs no
    /// fanfare.
    static func bounces(from old: Int, to new: Int, reduceMotion: Bool) -> Bool {
        new > old && !reduceMotion
    }

    /// A busy court's glow: a halo (`hooprCourtGlow`) that swells out of the
    /// dot and fades, once every `period`, like a sonar ping.
    ///
    /// **One curve for both screens.** Home's hot list draws it in SwiftUI
    /// (`CourtGlowHalo`) and the map's pins in Core Animation
    /// (`CourtMarkerView`), which samples `samples(count:)` into a keyframe
    /// animation rather than approximating the curve with a timing function —
    /// so a court pulses identically on both. Both phase it off the reference
    /// date, so every glowing court on a screen pulses together rather than
    /// each starting when it scrolled in.
    enum Glow {
        /// Slow enough to read as ambient rather than as an alert.
        static let period: TimeInterval = 2.0
        /// How far the halo swells, as a multiple of the dot it sits behind.
        static let peakScale: CGFloat = 2.2
        /// The halo's opacity as it leaves the dot, fading to nothing. Before
        /// `hooprCourtGlow`'s own alpha, which is what makes the same curve
        /// right on white and on black — see there.
        static let peakOpacity: Double = 0.85
        /// Under Reduce Motion the halo holds still, about where it would be
        /// halfway through a ping — still a glow, never a movement.
        static let restingScale: CGFloat = 1.8
        static let restingOpacity: Double = 0.4

        struct Frame: Equatable {
            let scale: CGFloat
            let opacity: Double
        }

        /// Where the halo is `elapsed` seconds into any cycle. Ease-out, so it
        /// leaves the dot quickly and slows as it fades.
        static func frame(at elapsed: TimeInterval, reduceMotion: Bool) -> Frame {
            if reduceMotion {
                return Frame(scale: restingScale, opacity: restingOpacity)
            }
            var progress = elapsed.truncatingRemainder(dividingBy: period) / period
            if progress < 0 { progress += 1 }
            return frame(atProgress: progress)
        }

        /// `count + 1` evenly spaced frames across one cycle, both ends
        /// included — the keyframe values `CourtMarkerView` animates through.
        static func samples(count: Int) -> [Frame] {
            let steps = max(count, 1)
            return (0...steps).map { frame(atProgress: Double($0) / Double(steps)) }
        }

        /// How far into the current cycle the reference clock is, so a halo
        /// started now joins the others in phase.
        static func phase(at date: Date) -> TimeInterval {
            let offset = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            return offset < 0 ? offset + period : offset
        }

        private static func frame(atProgress progress: Double) -> Frame {
            let eased = 1 - (1 - progress) * (1 - progress)
            return Frame(
                scale: 1 + (peakScale - 1) * CGFloat(eased),
                opacity: peakOpacity * (1 - eased)
            )
        }
    }

    /// The empty-state map's slow wander (`TonightNearbyPreview`): an ellipse
    /// traced once every `period`, so the loop has no seam to jump at.
    ///
    /// **An offset, not a camera move.** The map is drawn `overscan` larger
    /// than its frame on every side and slid inside the clip, which costs a
    /// transform per frame instead of a MapKit camera change — and never asks
    /// for new tiles mid-scroll. `amplitude` stays under `overscan`, so no
    /// edge of the map is ever uncovered.
    ///
    /// Phased off the reference date, like `Glow`, so the frame doesn't jump
    /// back to the start each time the preview scrolls in.
    enum Drift {
        /// Slow enough that the movement is felt rather than watched.
        static let period: TimeInterval = 24
        /// How far the map wanders across, in points. Down is
        /// `verticalRatio` of that, because the frame is wide and short.
        static let amplitude: CGFloat = 10
        static let verticalRatio: CGFloat = 0.6
        /// How much larger than its frame the map is drawn, per side.
        static let overscan: CGFloat = 14

        /// Where the map sits at `date`. Still under Reduce Motion — the frame
        /// it rests on is the centred one.
        static func offset(at date: Date, reduceMotion: Bool) -> CGSize {
            if reduceMotion { return .zero }
            var progress = date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            if progress < 0 { progress += 1 }
            let angle = progress * 2 * .pi
            return CGSize(
                width: amplitude * CGFloat(cos(angle)),
                height: amplitude * verticalRatio * CGFloat(sin(angle))
            )
        }
    }
    /// Home's stats scoreboard (`StatsScoreboard`): how long a panel holds,
    /// and how the next one arrives.
    enum Scoreboard {
        /// Long enough to read a label and a number twice; short enough that
        /// five panels come round in under half a minute.
        static let dwell: TimeInterval = 4

        /// Whether the panels take turns at all, or are shown all at once.
        ///
        /// All at once under Reduce Motion, and under VoiceOver — which reads
        /// the screen as one sentence, so a picture changing under it would
        /// say something the sentence doesn't.
        static func isStatic(reduceMotion: Bool, voiceOver: Bool) -> Bool {
            reduceMotion || voiceOver
        }

        /// Whether the next panel is due to come in. Only with something to
        /// rotate to, not paused, on screen, with the app in front — the timer
        /// is the only cost this has, so it never runs for nobody.
        static func advances(
            panelCount: Int,
            isPaused: Bool,
            isOnScreen: Bool,
            isActive: Bool,
            reduceMotion: Bool,
            voiceOver: Bool
        ) -> Bool {
            panelCount > 1 && !isPaused && isOnScreen && isActive
                && !isStatic(reduceMotion: reduceMotion, voiceOver: voiceOver)
        }

        /// The next panel slides in across the screen as this one slides out,
        /// like a board changing over. A cross-fade under Reduce Motion —
        /// which doesn't rotate, so this is only a guard.
        static func slide(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .push(from: .trailing)
        }
    }
}

extension Animation {
    /// `Motion.Kind.move`, honouring Reduce Motion.
    static var hooprSpring: Animation {
        Motion.animation(.move, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// `Motion.Kind.snap`, honouring Reduce Motion.
    static var hooprSnap: Animation {
        Motion.animation(.snap, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// `Motion.Kind.swap`, honouring Reduce Motion.
    static var hooprSwap: Animation {
        Motion.animation(.swap, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
}

extension AnyTransition {
    /// `Motion.lift`, honouring Reduce Motion.
    static var hooprLift: AnyTransition {
        Motion.lift(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// `Motion.pop`, honouring Reduce Motion.
    static var hooprPop: AnyTransition {
        Motion.pop(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
}

/// Press feedback for a filled button: it shrinks a little and dims while
/// held, and springs back on release. Under Reduce Motion it only dims.
///
/// For buttons that draw their own fill — a capsule, a card — which
/// `.buttonStyle(.plain)` left with no pressed state at all. A disabled button
/// keeps whatever its own label does for that state; this adds nothing to it.
struct HooprPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hooprPressFeedback(isPressed: configuration.isPressed)
    }
}

extension View {
    /// `HooprPressStyle`'s press, for a `ButtonStyle` that draws more than the
    /// press — `HooprButtonStyle` — so every button in the app is pressed the
    /// same way.
    func hooprPressFeedback(isPressed: Bool) -> some View {
        modifier(PressFeedback(isPressed: isPressed))
    }
}

private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && Motion.pressScales(reduceMotion: reduceMotion) ? Motion.pressedScale : 1)
            .opacity(isPressed ? Motion.pressedOpacity : 1)
            .animation(Motion.animation(.snap, reduceMotion: reduceMotion), value: isPressed)
    }
}

extension ButtonStyle where Self == HooprPressStyle {
    static var hooprPress: HooprPressStyle { HooprPressStyle() }
}

extension View {
    /// Animates a number's change by rolling its digits — up when it rises,
    /// down when it falls — and nothing on first appearance: the roll is
    /// attached to `value` changing. Under Reduce Motion the digits cross-fade
    /// instead.
    func hooprNumericTransition(_ value: Int) -> some View {
        modifier(NumericTransition(key: value, direction: Double(value)))
    }

    /// The same, for text made of numbers that isn't one number — a record,
    /// "3–1" — keyed on the text itself.
    func hooprNumericTransition(text value: String) -> some View {
        modifier(NumericTransition(key: value, direction: nil))
    }
}

private struct NumericTransition<Key: Equatable>: ViewModifier {
    let key: Key
    let direction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(transition)
            .animation(Motion.animation(.snap, reduceMotion: reduceMotion), value: key)
    }

    private var transition: ContentTransition {
        if reduceMotion { return .opacity }
        if let direction { return .numericText(value: direction) }
        return .numericText()
    }
}

extension View {
    /// Bounces an SF Symbol once when `value` rises — a new request, a new
    /// arrival — per `Motion.bounces(from:to:reduceMotion:)`. Nothing on first
    /// appearance: it listens for a change.
    func hooprBounce(onRiseOf value: Int) -> some View {
        modifier(BounceOnRise(value: value))
    }
}

private struct BounceOnRise: ViewModifier {
    let value: Int
    @State private var bounces = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, value: bounces)
            .onChange(of: value) { old, new in
                if Motion.bounces(from: old, to: new, reduceMotion: reduceMotion) {
                    bounces += 1
                }
            }
    }
}

extension View {
    /// A card in a scrolling list is at full strength while it's wholly on
    /// screen, and eases back — fainter, a touch smaller — as it crosses the
    /// top or bottom edge, so the edge of the list reads as an edge rather than
    /// a cut. Driven by the scroll position, not a clock, so it can't lag a
    /// fast flick. Under Reduce Motion only the fade remains.
    func hooprScrollLift() -> some View {
        modifier(ScrollLift())
    }
}

private struct ScrollLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Read here, not in the closure: it runs off the main actor.
        let scales = !reduceMotion
        let edgeOpacity = Motion.scrollEdgeOpacity
        let edgeScale = Motion.scrollEdgeScale
        return content.scrollTransition(.interactive, axis: .vertical) { effect, phase in
            effect
                .opacity(phase.isIdentity ? 1 : edgeOpacity)
                .scaleEffect(phase.isIdentity || !scales ? 1 : edgeScale)
        }
    }
}

// MARK: - Card to detail

extension View {
    /// Marks this view as where a push zooms out of — the card or band a
    /// detail screen opens from (`hooprZoomDestination`).
    func hooprZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }

    /// A pushed screen that grows out of the view it was opened from, and
    /// shrinks back into it — the continuity between a card and its detail.
    /// Under Reduce Motion, the ordinary push.
    func hooprZoomDestination<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomDestination(sourceID: sourceID, namespace: namespace))
    }
}

private struct ZoomDestination<ID: Hashable>: ViewModifier {
    let sourceID: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}
