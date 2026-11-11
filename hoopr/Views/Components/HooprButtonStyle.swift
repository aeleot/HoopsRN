import SwiftUI

/// The app's filled button (UI revamp Phase 6).
///
/// **Why it exists.** The Phase 0 audit found the
/// filled button built from scratch at six heights and four corner radii, and
/// by Phase 5 it was fifteen hand-built copies at five heights (36, 42, 44, 48,
/// 52) in two shapes. Now a button says what size and what job it is, and this
/// decides how that looks:
///
/// - **`Size`** — `compact` sits in a row or a card beside other content
///   (Invite, Join, a run's Join/Leave/Cancel); `regular` is a lone action at
///   its label's width (Find a court, Create a squad); `large` is a screen's or
///   sheet's main action across its width (We're here, Queue up, Sign In).
///   Every size has a 44pt tap target; `compact` draws smaller inside it.
/// - **`Role`** — four pairings, each one `ThemeContrastTests` asserts:
///   `primary` (`hooprOnBrand` on `hooprOrange`), `secondary` (primary text on
///   `hooprFill`), `destructive` (`hooprRed` on `hooprFill` — a leave or cancel
///   isn't an error, so the red is the label, never the fill), and
///   `unavailable` (secondary text on `hooprFill`: Sign In before the form is
///   complete).
/// - **`Shape`** — **a capsule, except a form's submit** (the user's call,
///   2026-09-24). A submit that sits under rounded text fields — Login,
///   password reset — keeps the fields' 12pt corners so the form reads as one
///   object; everywhere else, a capsule.
///
/// **The label owns only its content.** Type, colour, padding, height, shape,
/// the tap target and the press all come from here — so a call site passes a
/// `Text`, or an icon beside one, with no font and no colour. An icon inherits
/// the label's font, which is what keeps it the text's size. A spinner inherits
/// the role's colour through `tint`.
///
/// **Disabled isn't drawn here**, because the app has two kinds and they look
/// different on purpose: *pending* (the write is in flight — full colour, a
/// spinner) and *blocked* (another write is — the caller dims it). A style can
/// only see `isEnabled`, which can't tell them apart.
struct HooprButtonStyle: ButtonStyle {
    enum Size: CaseIterable {
        case compact
        case regular
        case large

        /// The drawn height, a floor — the label grows it at larger text sizes
        /// rather than being cut off.
        var height: CGFloat {
            switch self {
            case .compact: return 36
            case .regular: return 44
            case .large:   return 52
            }
        }

        /// What a thumb has to hit. Never below 44, whatever is drawn.
        var tapTarget: CGFloat { max(height, HooprButtonStyle.minimumTapTarget) }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 14
            case .regular, .large: return Spacing.xl
            }
        }

        /// A `large` button spans its container unless told otherwise; the
        /// others hug their label.
        var fillsWidthByDefault: Bool { self == .large }
    }

    enum Role: CaseIterable {
        case primary
        case secondary
        case destructive
        case unavailable

        var foreground: Color {
            switch self {
            case .primary:     return .hooprOnBrand
            case .secondary:   return .hooprPrimaryText
            case .destructive: return .hooprRed
            case .unavailable: return .hooprSecondaryText
            }
        }

        var background: Color {
            switch self {
            case .primary: return .hooprOrange
            case .secondary, .destructive, .unavailable: return .hooprFill
            }
        }

        /// A secondary button carries a `hooprBorder` edge — "Mark complete"
        /// beside a run's Join, Directions beside Start Run — so it reads as a
        /// control and not as a grey patch: `hooprFill` on a white card is
        /// 1.09:1. The others are either filled or carry a coloured label.
        var hasEdge: Bool { self == .secondary }
    }

    enum Shape {
        case capsule
        /// A form's submit, matching the rounded fields above it
        /// (`HooprField.cornerRadius`).
        case form
    }

    /// The app's tap-target floor (Apple's HIG minimum).
    static let minimumTapTarget: CGFloat = 44

    let size: Size
    let role: Role
    let shape: Shape
    let fillsWidth: Bool

    init(_ size: Size, role: Role = .primary, shape: Shape = .capsule, fillsWidth: Bool? = nil) {
        self.size = size
        self.role = role
        self.shape = shape
        self.fillsWidth = fillsWidth ?? size.fillsWidthByDefault
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(LabelType(size: size))
            .multilineTextAlignment(.center)
            .foregroundStyle(role.foreground)
            .tint(role.foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: size.height)
            .background(role.background, in: outline)
            .overlay {
                if role.hasEdge {
                    outline.stroke(Color.hooprBorder, lineWidth: 1)
                }
            }
            // The target reaches past a compact button's drawn edge, so it
            // stays 44pt tall without drawing 44pt tall.
            .frame(minHeight: size.tapTarget)
            .contentShape(Rectangle())
            .hooprPressFeedback(isPressed: configuration.isPressed)
    }

    private var outline: AnyShape {
        switch shape {
        case .capsule: return AnyShape(Capsule())
        case .form:    return AnyShape(RoundedRectangle(cornerRadius: HooprField.cornerRadius))
        }
    }

    /// Type per size. `large` is `subhead` — 17pt semibold, the size a main
    /// action has on iOS — and `regular` the body size in semibold. `compact`
    /// has no role at 14pt, so it names the size.
    private struct LabelType: ViewModifier {
        let size: Size

        func body(content: Content) -> some View {
            switch size {
            case .compact:
                content.hooprFont(14, weight: .semibold)
            case .regular:
                content.hooprType(.body).fontWeight(.semibold)
            case .large:
                content.hooprType(.subhead)
            }
        }
    }
}

extension ButtonStyle where Self == HooprButtonStyle {
    /// `.buttonStyle(.hooprFilled(.large))` — see `HooprButtonStyle`.
    static func hooprFilled(
        _ size: HooprButtonStyle.Size,
        role: HooprButtonStyle.Role = .primary,
        shape: HooprButtonStyle.Shape = .capsule,
        fillsWidth: Bool? = nil
    ) -> HooprButtonStyle {
        HooprButtonStyle(size, role: role, shape: shape, fillsWidth: fillsWidth)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        ForEach(HooprButtonStyle.Role.allCases, id: \.self) { role in
            HStack {
                Button("Invite") {}.buttonStyle(.hooprFilled(.compact, role: role))
                Button("Find a court") {}.buttonStyle(.hooprFilled(.regular, role: role))
            }
        }
        Button("Queue up") {}.buttonStyle(.hooprFilled(.large))
        Button("Sign In") {}.buttonStyle(.hooprFilled(.large, shape: .form))
    }
    .padding()
    .background(Color.hooprBackground)
}
