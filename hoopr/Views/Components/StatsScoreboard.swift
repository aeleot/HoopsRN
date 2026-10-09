import SwiftUI
import UIKit

/// Home's stats as a scoreboard: a screen set into a card's bezel, its
/// panels taking turns — this week, your squad's record, the streak, the
/// total, the last run (2026-10-05, replacing the three-column stats card).
///
/// **Two tiers of number, by the user's call.** The squad's record is a query
/// over results two leaders confirmed, so it takes the `numeral` tier the band
/// and squad home use for it. The run stats are self-reported counters the
/// owner's client writes, so they stop a step below, at `title` — big enough
/// for a scoreboard, never as authoritative as the record beside them.
///
/// **It shares its row with the run calendar's tile** (2026-10-06), so it is
/// narrower than Home's full width while the tile is beside it, and as tall as
/// it always was. Whether the tile fits beside it is a function of the text size
/// (`HomeStatsLayout`), measured with `StatsScoreboardMetrics`.
///
/// **One panel at a time, and the slide is the only motion** (`Motion.Scoreboard`).
/// A panel holds for `dwell` seconds, then the next slides across as it slides
/// out. That is moving text, so it is bounded hard:
///
/// - **A pause control**, always on the screen while it rotates — WCAG 2.2.2
///   asks for one on anything that moves on its own beside other content.
/// - **No rotation at all under Reduce Motion or VoiceOver**: every panel is
///   shown at once instead, as a list on the same screen. VoiceOver reads the
///   whole board as one sentence either way.
/// - **No timer for nobody**: none while the board is scrolled away, the app is
///   in the background, or there is only one panel. Between slides nothing is
///   animating at all — the timer is a sleeping task, not a frame clock.
///
/// **The screen keeps its tallest panel's height**, so the card below doesn't
/// jump each time a numeral panel follows a title one: every panel is laid out,
/// hidden, underneath the one on show.
///
/// The screen follows the appearance (`Theme.swift`, "Scoreboard"): near-black
/// in dark mode, a pale panel in light (2026-10-06 — it was fixed near-black,
/// and in light mode read as dark mode left behind). Every colour on it is
/// asserted in `ThemeContrastTests`, in both appearances.
struct StatsScoreboard: View {
    let stats: [HomeViewModel.ScoreboardStat]
    /// Stretched to the height of the tile beside it, when that is taller.
    var fillsHeight = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var index = 0
    @State private var isPaused = false
    @State private var isOnScreen = true

    var body: some View {
        ScoreboardHousing(fillsHeight: fillsHeight) {
            screenContent
        }
        .onScrollVisibilityChange(threshold: 0.5) { isOnScreen = $0 }
        // Restarts whenever the board becomes due or stops being due — a
        // pause, a scroll away, the app backgrounding, a setting changing —
        // **and whenever the panels change.** The task runs on the view as
        // it was when it started, so without the panels in its key it kept
        // counting the four it began with after a squad's record arrived
        // as a fifth, and never showed the last one (seen on the device,
        // 2026-10-05).
        .task(id: RotationKey(advances: advances, panels: stats.map(\.kind))) {
            await advanceWhileDue()
        }
        .onChange(of: stats.map(\.kind)) { _, kinds in
            if index >= kinds.count { index = 0 }
        }
    }

    // MARK: - Rotation

    /// What the rotation task is restarted on — see `body`.
    private struct RotationKey: Hashable {
        let advances: Bool
        let panels: [HomeViewModel.ScoreboardStat.Kind]
    }

    private var isStatic: Bool {
        Motion.Scoreboard.isStatic(reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    private var advances: Bool {
        Motion.Scoreboard.advances(
            panelCount: stats.count,
            isPaused: isPaused,
            isOnScreen: isOnScreen,
            isActive: scenePhase == .active,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver
        )
    }

    /// Sleeps a dwell, slides the next panel in, and again — until the task is
    /// cancelled, which `.task(id:)` does the moment `advances` turns false.
    private func advanceWhileDue() async {
        guard advances else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Motion.Scoreboard.dwell))
            guard !Task.isCancelled, !stats.isEmpty else { return }
            withAnimation(Motion.animation(.swap, reduceMotion: reduceMotion)) {
                index = (index + 1) % stats.count
            }
        }
    }

    private var current: HomeViewModel.ScoreboardStat? {
        stats.isEmpty ? nil : stats[min(index, stats.count - 1)]
    }

    // MARK: - The screen

    /// What the screen shows. The housing around it — the padding, the LED
    /// grid, the clip the slide passes under, the bezel — is
    /// `ScoreboardHousing`, shared with the run calendar.
    private var screenContent: some View {
        Group {
            if isStatic || stats.count < 2 {
                allAtOnce
            } else {
                rotating
            }
        }
    }

    /// Reduce Motion, VoiceOver, or a single panel: every panel, one under
    /// another. Still a scoreboard — just one that isn't changing over.
    private var allAtOnce: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(stats) { stat in
                panel(stat, reservesPause: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenBoard)
    }

    private var rotating: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // The sizer: every panel, laid out and hidden, so the screen
                // holds the tallest one's height whichever is showing.
                ForEach(stats) { stat in
                    panel(stat, reservesPause: true).hidden()
                }

                if let current {
                    panel(current, reservesPause: true)
                        .id(current.kind)
                        .transition(Motion.Scoreboard.slide(reduceMotion: reduceMotion))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenBoard)

            // The gap the marks always had — more when the screen is stretched
            // to the tile's height, which keeps them on the bottom edge.
            Spacer(minLength: Spacing.md)

            pageMarks
        }
        .overlay(alignment: .topTrailing) { pauseButton }
    }

    /// "Your stats. 3 runs done this week. Hornets, 4 wins, 1 loss this season. …" —
    /// the whole board, whichever panel is showing.
    private var spokenBoard: String {
        (["Your stats"] + stats.map(\.spoken)).joined(separator: ". ")
    }

    // MARK: - A panel

    private func panel(_ stat: HomeViewModel.ScoreboardStat, reservesPause: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                if let standing = stat.standing {
                    SquadCrest(squad: standing.squad, size: SquadCrest.Size.inline)
                } else if let symbol = Self.symbol(for: stat.kind) {
                    Image(systemName: symbol)
                        .hooprType(.label)
                        .foregroundStyle(Color.hooprScoreboardLabel)
                }

                Text(stat.label)
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprScoreboardLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Clear of the pause control in the corner.
            .padding(.trailing, reservesPause ? StatsScoreboardMetrics.pauseReserve : 0)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                valueText(stat)
                    .hooprType(Self.role(for: stat.kind))
                    .monospacedDigit()
                    .foregroundStyle(Color.hooprScoreboardText)
                    .hooprNumericTransition(text: stat.value)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let unit = stat.unit {
                    Text(unit)
                        .hooprType(.headline)
                        .foregroundStyle(Color.hooprScoreboardDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A record's dash is set as a separator, as on the band; everything else
    /// is its value as written.
    private func valueText(_ stat: HomeViewModel.ScoreboardStat) -> Text {
        if let record = stat.standing?.record {
            return SquadRecordLine.recordText(record, dynamicTypeSize: dynamicTypeSize, dashColor: .hooprScoreboardDim)
        }
        return Text(stat.value)
    }

    /// The confirmed record takes the numeral; self-reported counts stop a
    /// step below it. See the type's note.
    static func role(for kind: HomeViewModel.ScoreboardStat.Kind) -> HooprTextRole {
        StatsScoreboardMetrics.role(for: kind)
    }

    /// The label's symbol — the stats card's icons, kept (the user missed
    /// them once when a redesign dropped them). The squad shows its crest.
    static func symbol(for kind: HomeViewModel.ScoreboardStat.Kind) -> String? {
        StatsScoreboardMetrics.symbol(for: kind)
    }

    // MARK: - Controls

    /// Which panel is up, as a row of LED marks: the current one long and lit,
    /// the others short and dim. A picture of the position — VoiceOver reads
    /// the whole board instead.
    private var pageMarks: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { offset, _ in
                let isCurrent = offset == min(index, stats.count - 1)
                Capsule()
                    .fill(isCurrent ? Color.hooprScoreboardLabel : Color.hooprScoreboardDim)
                    .frame(width: isCurrent ? 14 : 5, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    /// Pause and play. A 44pt target in the screen's corner, its glyph at a
    /// unit's dimness so it never competes with the number.
    private var pauseButton: some View {
        Button {
            isPaused.toggle()
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .hooprFont(13, weight: .bold, maximumSize: 17)
                .foregroundStyle(Color.hooprScoreboardDim)
                .frame(width: StatsScoreboardMetrics.pauseTarget, height: StatsScoreboardMetrics.pauseTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hooprPress)
        // Into the corner of the screen's padding, so the target is full size
        // without pushing the panel down.
        .offset(x: StatsScoreboardMetrics.pauseInset, y: -StatsScoreboardMetrics.pauseInset)
        .accessibilityLabel(isPaused ? "Play the scoreboard" : "Pause the scoreboard")
    }
}

/// A screen set into a card's bezel: the housing Home's scoreboard, its
/// calendar tile and the month popup's grid all draw on, so they are the
/// identical object and not copies that could drift.
///
/// `fillsHeight` is for the scoreboard and the tile side by side, where the
/// shorter is stretched to the taller one's height.
struct ScoreboardHousing<Content: View>: View {
    var fillsHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(StatsScoreboardMetrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background { ScoreboardScreen() }
            // The screen's own clip is what the slide passes under.
            .clipShape(RoundedRectangle(cornerRadius: StatsScoreboardMetrics.screenCornerRadius, style: .continuous))
            .padding(StatsScoreboardMetrics.bezel)
            .frame(maxHeight: fillsHeight ? .infinity : nil)
            .cardChrome()
    }
}

/// The screen: near-black in dark mode and pale in light, with a faint grid
/// of unlit LEDs. Drawn once per size — nothing on it animates. Decorative:
/// hidden from VoiceOver, and it never takes a touch.
struct ScoreboardScreen: View {
    var body: some View {
        Canvas { context, size in
            let pitch = StatsScoreboardMetrics.dotPitch
            let diameter = StatsScoreboardMetrics.dotDiameter
            var dots = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
                    x += pitch
                }
                y += pitch
            }
            context.fill(dots, with: .color(.hooprScoreboardDot))
        }
        .background(Color.hooprScoreboardScreen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The scoreboard's geometry, and the measurement that every value and every
/// run panel's label fits on one line of the screen at every text size — so a
/// number never breaks, "Yesterday" never becomes "Yester / day", and "Done
/// this week" never drops "week" to a second line.
nonisolated enum StatsScoreboardMetrics {
    /// The card's rim around the screen.
    static let bezel: CGFloat = 6
    /// Concentric with the card's corner.
    static let screenCornerRadius: CGFloat = CardChrome.cornerRadius - bezel
    /// Inside the screen, around the panel. `Spacing.lg`.
    static let screenPadding: CGFloat = 16

    static let pauseTarget: CGFloat = 44
    /// How far the pause target reaches into the screen's padding.
    static let pauseInset: CGFloat = 12
    /// What a panel's label row leaves clear for it.
    static let pauseReserve: CGFloat = pauseTarget - pauseInset

    /// The unlit LEDs.
    static let dotPitch: CGFloat = 4
    static let dotDiameter: CGFloat = 1.6

    /// The width a value line has inside a card `cardWidth` wide: less the
    /// bezel and the screen's padding on each side.
    static func innerWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth - (bezel + screenPadding) * 2
    }

    /// The confirmed record takes the numeral; self-reported counts stop a step
    /// below it, at `title`. Here rather than on the view so a nonisolated
    /// measurement can ask it.
    static func role(for kind: HomeViewModel.ScoreboardStat.Kind) -> HooprTextRole {
        kind == .squad ? .numeral : .title
    }

    /// The label's symbol. Here rather than on the view, like `role(for:)`, so
    /// the label measurement below can ask it.
    static func symbol(for kind: HomeViewModel.ScoreboardStat.Kind) -> String? {
        switch kind {
        case .thisWeek: return "calendar"
        case .squad: return nil
        case .streak: return "flame.fill"
        case .total: return "basketball.fill"
        case .lastRun: return "clock.fill"
        }
    }

    /// The widest value each panel realistically shows, with its unit.
    static let worstCase: [(kind: HomeViewModel.ScoreboardStat.Kind, value: String, unit: String?)] = [
        (.thisWeek, "12", "runs"),
        (.squad, "12 – 10", nil),
        (.streak, "52", "wks"),
        (.total, "1280", "runs"),
        (.lastRun, "Yesterday", nil),
    ]

    /// A value and its unit side by side, as `StatsScoreboard.panel` sets them.
    /// The record is measured with a full-size dash, which is wider than the
    /// 60% one drawn — so this errs toward not fitting.
    static func lineWidth(value: String, unit: String?, role: HooprTextRole, at category: UIContentSizeCategory) -> CGFloat {
        let valueWidth = width(of: value, role: role, at: category)
        guard let unit else { return valueWidth }
        return valueWidth + Spacing.sm + width(of: unit, role: .headline, at: category)
    }

    /// Whether every value the board can show fits one line of a card
    /// `cardWidth` wide at `category` — what `HomeStatsLayout` asks before it
    /// puts the calendar tile beside the board.
    static func everyValueFits(cardWidth: CGFloat, at category: UIContentSizeCategory) -> Bool {
        worstCase.allSatisfy { line in
            lineWidth(value: line.value, unit: line.unit, role: role(for: line.kind), at: category)
                <= innerWidth(cardWidth: cardWidth)
        }
    }

    /// The run panels' labels, taken from `HomeViewModel.scoreboardStats` itself
    /// so a renamed label is measured as written, never as a copy.
    ///
    /// **Labels were not measured until 2026-10-09**, when "This week" became
    /// "Done this week": 115pt at the default size against the 119pt the panel
    /// has beside the calendar tile, and 133pt at `.extraLarge` against 116pt.
    /// The squad panel's label is the squad's own name — any length the create
    /// form allows — so it wraps rather than being held to a line here.
    static var runPanelLabels: [(kind: HomeViewModel.ScoreboardStat.Kind, label: String)] {
        HomeViewModel.scoreboardStats(
            completedCount: 1,
            runsThisWeek: 1,
            streak: 1,
            lastCompletedText: "—",
            squadStanding: nil
        )
        .map { ($0.kind, $0.label) }
    }

    /// A label row as `StatsScoreboard.panel` sets it: the symbol, a
    /// `Spacing.sm` gap, and the label in the `label` role — uppercased and
    /// tracked, as `hooprType(.label)` draws it.
    static func labelWidth(_ label: String, symbol: String?, at category: UIContentSizeCategory) -> CGFloat {
        let role = HooprTextRole.label
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let font = UIFont.systemFont(ofSize: size, weight: role.uiFontWeight)
        let text = role.isUppercase ? label.uppercased() : label
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font, .kern: role.kerning]).width)

        guard let symbol,
              let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font))
        else { return textWidth }
        return ceil(image.size.width) + Spacing.sm + textWidth
    }

    /// Whether every run panel's label fits one line of a card `cardWidth`
    /// wide at `category`, clear of the pause control — what `HomeStatsLayout`
    /// asks beside `everyValueFits`.
    static func everyLabelFits(cardWidth: CGFloat, at category: UIContentSizeCategory) -> Bool {
        let available = innerWidth(cardWidth: cardWidth) - pauseReserve
        return runPanelLabels.allSatisfy { panel in
            labelWidth(panel.label, symbol: symbol(for: panel.kind), at: category) <= available
        }
    }

    static func width(of text: String, role: HooprTextRole, at category: UIContentSizeCategory) -> CGFloat {
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: role.uiFontWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
