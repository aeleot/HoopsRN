import SwiftUI

/// The app's small capsule label — HOSTING, WAITLIST, FULL, "3 SPOTS" (UI
/// revamp Phase 6).
///
/// The audit found "five spellings of a small pill
/// with a word in it". By Phase 5 the run-status pill was still built by hand
/// on Home, the Runs card and the map's court card — each with its own copy of
/// the rule for *which* status wins — plus a filled variant on the map's "Now"
/// rows at a slightly different size. One component now, in two styles:
///
/// - **`tinted`** — the label's colour over a wash of a tint: a status to
///   notice, not act on. The wash strength depends on the ground (`Ground`),
///   and `ThemeContrastTests` reads the same constants it draws with.
/// - **`filled`** — a solid capsule, for a status that *is* the decision the
///   row is read for (room on a run, on the map's "Now" list).
///
/// Always `badge` type — 11pt bold, uppercased by `textCase` so VoiceOver reads
/// the word rather than spelling it — capped, one line, never broken.
///
/// **Not the amenity chips** (`CourtBadges`): those are regular-weight,
/// mixed-case facts about a court, on a neutral fill or a caution outline — a
/// different job, and a component of their own already.
struct HooprBadge: View {
    enum Style {
        case tinted(foreground: Color, wash: Color, ground: Ground)
        case filled(foreground: Color, fill: Color)
    }

    /// What the badge sits on, which decides how strong its wash may be.
    enum Ground {
        /// A card or sheet — `hooprSurface`.
        case surface
        /// A hero band (Home's). Lighter than a card in dark mode, and the
        /// 12% wash measured 4.44:1 on it; 8% clears.
        case band

        var washOpacity: Double {
            switch self {
            case .surface: return HooprBadge.washOnSurface
            case .band:    return HooprBadge.washOnBand
            }
        }
    }

    /// The wash strengths, named so the contrast tests and the drawing can't
    /// disagree.
    static let washOnSurface: Double = 0.12
    static let washOnBand: Double = 0.08

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .hooprType(.badge)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.Pill.horizontal)
            .padding(.vertical, Spacing.Pill.vertical)
            .background(Capsule().fill(fill))
    }

    private var foreground: Color {
        switch style {
        case .tinted(let foreground, _, _): return foreground
        case .filled(let foreground, _):    return foreground
        }
    }

    private var fill: Color {
        switch style {
        case .tinted(_, let wash, let ground): return wash.opacity(ground.washOpacity)
        case .filled(_, let fill):             return fill
        }
    }
}

// MARK: - A run's status

/// Your standing on a run, as its badge says it — or nothing, when there's
/// nothing to flag.
///
/// **One priority order, here.** Home, the Runs card and the map's court card
/// each carried this ladder, and Home's comment said it was mirroring
/// `GameCard`'s by hand. Your own relationship to the run says more than its
/// status does, so hosting beats the waitlist, and both beat "full".
nonisolated enum RunStatus: Equatable, CaseIterable {
    case hosting
    case waitlisted
    case full

    static func of(isHost: Bool, isWaitlisted: Bool, isFull: Bool) -> RunStatus? {
        if isHost { return .hosting }
        if isWaitlisted { return .waitlisted }
        if isFull { return .full }
        return nil
    }

    var text: String {
        switch self {
        case .hosting:    return "Hosting"
        case .waitlisted: return "Waitlist"
        case .full:       return "Full"
        }
    }
}

extension RunStatus {
    /// **The label and the wash are separate colours**, because the text has
    /// to be *read* and the ground behind it is a fill. HOSTING's text is
    /// `hooprBrandAccent` (4.87:1 on its own 12% wash in light, 4.90:1 in
    /// dark) over a wash of the vivid `hooprOrange`; drawn as orange on that
    /// wash it measured 2.78:1 in light mode. The other two are secondary text
    /// on a wash of itself. `ThemeContrastTests` asserts each on both grounds.
    var foreground: Color {
        self == .hosting ? .hooprBrandAccent : .hooprSecondaryText
    }

    var wash: Color {
        self == .hosting ? .hooprOrange : .hooprSecondaryText
    }
}

extension HooprBadge {
    init(_ status: RunStatus, on ground: Ground) {
        self.init(
            text: status.text,
            style: .tinted(foreground: status.foreground, wash: status.wash, ground: ground)
        )
    }
}

// MARK: - Notification marks

/// A count of things waiting — the inbox's. White on red with a ring in the
/// page colour, so it reads as sitting on top of the glyph it's pinned to.
///
/// `hooprOnRed`, not `hooprOnBrand`: red is the one ground that inverts
/// between appearances.
struct HooprCountBadge: View {
    /// What to draw — the caller's to word (`InboxButton.badgeText(for:)`
    /// caps it at "9+"), not this view's.
    let text: String
    /// Drives the digits' roll when the count changes.
    let count: Int

    var body: some View {
        Text(text)
            .hooprFont(11, weight: .bold, maximumSize: 13)
            .hooprNumericTransition(count)
            .foregroundStyle(Color.hooprOnRed)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Color.hooprRed))
            .overlay(Capsule().stroke(Color.hooprBackground, lineWidth: HooprNotificationDot.ringWidth))
    }
}

/// "Something is waiting" with no number — the profile button's, until the
/// inbox took its slot; the component gallery still shows it. The same red
/// and the same ring as `HooprCountBadge`, at a fixed size.
struct HooprNotificationDot: View {
    static let diameter: CGFloat = 12
    static let ringWidth: CGFloat = 2

    var body: some View {
        Circle()
            .fill(Color.hooprRed)
            .stroke(Color.hooprBackground, lineWidth: Self.ringWidth)
            .frame(width: Self.diameter, height: Self.diameter)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        HStack {
            ForEach(RunStatus.allCases, id: \.self) { HooprBadge($0, on: .surface) }
        }
        HooprBadge(text: "3 spots", style: .filled(foreground: .hooprOnBrand, fill: .hooprOrange))
        HStack {
            HooprCountBadge(text: "3", count: 3)
            HooprCountBadge(text: "9+", count: 14)
            HooprNotificationDot()
        }
    }
    .padding()
    .background(Color.hooprSurface)
}
