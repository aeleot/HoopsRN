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
        PressedLabel(configuration: configuration)
    }

    private struct PressedLabel: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isPressed = configuration.isPressed
            configuration.label
                .scaleEffect(isPressed && Motion.pressScales(reduceMotion: reduceMotion) ? Motion.pressedScale : 1)
                .opacity(isPressed ? Motion.pressedOpacity : 1)
                .animation(Motion.animation(.snap, reduceMotion: reduceMotion), value: isPressed)
        }
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
