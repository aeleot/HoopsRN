import SwiftUI
import UIKit

/// The month the calendar tile opens, as one box over a dimmed Home
/// (2026-10-06, the user's design): the scoreboard's screen, holding the
/// month's name with its arrows and an X, the grid, a legend, and a footer
/// naming the selected day. Nothing else — a sheet, then a card holding a
/// second card and a list, were each more than a month needs.
///
/// **Every day has a zone** — a square around its number — and the zone says
/// what kind of day it was:
///
/// - **A dot for each run you are on**, up to three (`DayMark.maximumDots`).
/// - **Three or more runs set the day on fire**: the zone is a gradient from
///   the LED orange to `hooprScoreboardEmber` (`FireZone`).
/// - **A season game fills it with your squad's colour.** That outranks fire —
///   a match is the rarer, bigger thing — and the dots still count the runs.
///
/// On a lit zone the number and dots are the screen's own colour cut out of the
/// light on fire (near-black in dark mode, pale in light), and `hooprOnCrest` on
/// a game day; on an unlit one they are the screen's text. Every pairing is in
/// `ThemeContrastTests`, in both appearances. A game day's fill is
/// `hooprScoreboardSquad`: the crest colour on the dark screen, and the crest's
/// hue darkened until it stands off the pale one — a crest colour such as gold
/// (240,194,48) is 1.52:1 there. **Today is bold with a 2pt underline**; the
/// selected day is ringed in the screen's text colour, outside its zone, where
/// it reads against the screen whatever the zone's colour, and named in the
/// footer.
/// VoiceOver reads each day as a sentence — "Friday, October 9, 1 run, squad
/// game against Hornets" — so the colours and dots are hidden from it.
///
/// **Paging is the user's only**: the arrows beside the month's name, inside
/// `RunCalendarViewModel.bounds`, or a mostly-sideways swipe. The month
/// cross-fades on `Motion.animation(.swap, …)`.
///
/// **As tall as its month**, scrolling under the header only when the month
/// won't fit (`ViewThatFits`) — at the largest text sizes. It closes on the X,
/// a tap on the backdrop (`HomeTab`), or VoiceOver's escape gesture, and is
/// modal to VoiceOver, which lands on the X when it opens.
///
/// **The grid fits at every text size** (`RunCalendarMetrics.fits`): a column
/// is 47.7pt, past the 44pt a target needs, and the day numbers stop at
/// `dayNumberMaximumSize` so the largest sizes stay inside their zones.
struct RunCalendarPopup: View {
    typealias DayMark = RunCalendarViewModel.DayMark

    let page: RunCalendarViewModel.Page
    /// `1` forward a month, `-1` back.
    let onPage: (Int) -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The day picked by a tap. `nil` until then, and again after paging:
    /// `RunCalendarViewModel.defaultSelection(in:)` stands in.
    @State private var chosenDay: Int?

    /// VoiceOver lands on the popup when it opens, not on the page under it.
    @AccessibilityFocusState private var isCloseFocused: Bool

    /// The dots and the legend's swatches grow with the text beside them —
    /// the dots only until three of them fill a zone.
    @ScaledMetric(relativeTo: .caption) private var scaledDot = RunCalendarMetrics.dotDiameter
    @ScaledMetric(relativeTo: .caption) private var legendSwatch = RunCalendarMetrics.legendSwatch

    private var dotDiameter: CGFloat { min(scaledDot, RunCalendarMetrics.maximumDotDiameter) }

    private var selectedDay: Int {
        chosenDay ?? RunCalendarViewModel.defaultSelection(in: page)
    }

    var body: some View {
        ScoreboardHousing {
            VStack(spacing: Spacing.sm) {
                header

                // As tall as the month, unless the month won't fit: then the
                // popup takes the height there is, and the month scrolls under
                // the header — the X never scrolls away.
                ViewThatFits(in: .vertical) {
                    month
                    ScrollView { month }
                }
            }
            // The grid reaches past the screen's text inset so its columns
            // clear 44pt (`RunCalendarMetrics.gridBleed`); everything that
            // isn't the grid steps back in.
            .padding(.horizontal, -RunCalendarMetrics.gridBleed)
        }
        .shadow(color: Color.hooprShadow(opacity: 0.2), radius: 24, x: 0, y: 8)
        .simultaneousGesture(swipe)
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.vertical, Spacing.xxl)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear { isCloseFocused = true }
    }

    // MARK: - The header

    /// The month's name between its arrows, and the X.
    private var header: some View {
        HStack(spacing: 0) {
            pageButton(by: -1)

            Text(page.title)
                .hooprType(.headline)
                .foregroundStyle(Color.hooprScoreboardLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            pageButton(by: 1)

            Spacer(minLength: Spacing.sm)

            closeButton
        }
    }

    private func pageButton(by offset: Int) -> some View {
        let isBack = offset < 0
        let isEnabled = isBack ? page.canGoBack : page.canGoForward
        return Button {
            turnPage(by: offset)
        } label: {
            Image(systemName: isBack ? "chevron.left" : "chevron.right")
                .hooprFont(17, weight: .semibold, maximumSize: 22)
                // A dark arrow is a missing one: there is no month that way.
                .foregroundStyle(isEnabled ? Color.hooprScoreboardText : Color.hooprScoreboardDot)
                .frame(width: RunCalendarMetrics.minimumTarget, height: RunCalendarMetrics.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hooprPress)
        .disabled(!isEnabled)
        .accessibilityLabel(isBack ? "Previous month" : "Next month")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .hooprFont(13, weight: .bold, maximumSize: 17)
                .foregroundStyle(Color.hooprScoreboardText)
                .frame(width: RunCalendarPopupMetrics.closeDisc, height: RunCalendarPopupMetrics.closeDisc)
                .background(Color.hooprScoreboardDot, in: Circle())
                .frame(width: RunCalendarMetrics.minimumTarget, height: RunCalendarMetrics.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hooprPress)
        .accessibilityLabel("Close")
        .accessibilityFocused($isCloseFocused)
    }

    private func turnPage(by offset: Int) {
        withAnimation(Motion.animation(.swap, reduceMotion: reduceMotion)) {
            chosenDay = nil
            onPage(offset)
        }
    }

    /// A horizontal swipe pages, as the arrows do. Simultaneous with any scroll,
    /// and only a mostly sideways drag counts — a vertical one is the month
    /// scrolling.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: RunCalendarMetrics.swipeDistance)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 2 else { return }
                let offset = dx < 0 ? 1 : -1
                if offset < 0 ? page.canGoBack : page.canGoForward { turnPage(by: offset) }
            }
    }

    // MARK: - The month

    private var month: some View {
        VStack(spacing: Spacing.sm) {
            VStack(spacing: 0) {
                weekdays
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                            cell(day)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .id(page.month)
            .transition(.opacity)

            Group {
                legend
                status
                footer
            }
            .padding(.horizontal, RunCalendarMetrics.gridBleed)
        }
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(page.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .hooprType(.badge)
                    .foregroundStyle(Color.hooprScoreboardDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, Spacing.xs)
        .accessibilityHidden(true)
    }

    // MARK: - A day

    @ViewBuilder
    private func cell(_ day: Int?) -> some View {
        if let day {
            let isSelected = day == selectedDay

            Button {
                chosenDay = day
            } label: {
                zone(day, mark: page.marks[day] ?? DayMark(), isToday: day == page.today)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: RunCalendarMetrics.zoneCornerRadius + RunCalendarMetrics.zoneInset,
                                style: .continuous
                            )
                            .strokeBorder(Color.hooprScoreboardText, lineWidth: RunCalendarMetrics.selectionLine)
                            .padding(-RunCalendarMetrics.zoneInset)
                        }
                    }
                    .padding(RunCalendarMetrics.zoneInset)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page.spokenDays[day] ?? "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            // A blank before the 1st: nothing to draw, a pixel of height so the
            // row measures the same as its day cells.
            Color.clear.frame(height: 1)
        }
    }

    /// The square around a day's number: its fill says what kind of day it
    /// was, and the number and dots take the ink that reads on it.
    private func zone(_ day: Int, mark: DayMark, isToday: Bool) -> some View {
        let ink = Self.ink(on: mark.zone)

        return VStack(spacing: Spacing.hairline) {
            Text("\(day)")
                .hooprFont(
                    HooprTextRole.caption.size,
                    weight: isToday ? .bold : .regular,
                    maximumSize: RunCalendarMetrics.dayNumberMaximumSize
                )
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                // The underline's room is reserved on every day, so a row is
                // as tall whether or not today is in it.
                .padding(.bottom, RunCalendarMetrics.underlineGap + RunCalendarMetrics.underline)
                .overlay(alignment: .bottom) {
                    if isToday {
                        Rectangle()
                            .fill(ink)
                            .frame(height: RunCalendarMetrics.underline)
                    }
                }

            dots(mark.dots, color: mark.zone == .plain ? Color.hooprScoreboardLabel : ink)
        }
        .padding(.vertical, Spacing.xs)
        .frame(
            maxWidth: .infinity,
            minHeight: RunCalendarMetrics.minimumTarget - RunCalendarMetrics.zoneInset * 2
        )
        .background {
            zoneFill(mark.zone)
                .clipShape(RoundedRectangle(cornerRadius: RunCalendarMetrics.zoneCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func zoneFill(_ zone: DayMark.Zone) -> some View {
        switch zone {
        case .plain: Color.hooprScoreboardDot
        case .fire: FireZone()
        case .squad: Color.hooprScoreboardSquad(page.squadColorKey ?? Squad.defaultColorKey)
        }
    }

    /// What reads on each zone: the screen's own text on an unlit one, the
    /// screen's colour on fire, and the crest glyph's black on a game day.
    static func ink(on zone: DayMark.Zone) -> Color {
        switch zone {
        case .plain: Color.hooprScoreboardText
        case .fire: Color.hooprScoreboardScreen
        case .squad: Color.hooprOnCrest
        }
    }

    /// One dot per run, up to three, in a slot that is reserved whether or not
    /// there are any.
    private func dots(_ count: Int, color: Color) -> some View {
        HStack(spacing: RunCalendarMetrics.dotSpacing) {
            ForEach(0 ..< count, id: \.self) { _ in
                Circle()
                    .fill(color)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
        }
        .frame(height: dotDiameter)
        .accessibilityHidden(true)
    }

    // MARK: - Under the grid

    /// What the dots and the two lit zones mean. Hidden from VoiceOver, where
    /// every day already says what it holds.
    private var legend: some View {
        FlowLayout(spacing: Spacing.lg, lineSpacing: Spacing.xs) {
            legendItem("Run") {
                Circle()
                    .fill(Color.hooprScoreboardLabel)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
            legendItem("\(DayMark.fireRuns)+ runs") {
                FireZone().clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            if let key = page.squadColorKey {
                legendItem("Squad game") {
                    Color.hooprScoreboardSquad(key).clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func legendItem<Swatch: View>(_ label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: Spacing.xs) {
            swatch()
                .frame(width: legendSwatch, height: legendSwatch)
            Text(label)
                .hooprType(.caption)
                .foregroundStyle(Color.hooprScoreboardDim)
        }
    }

    /// What isn't an answer yet, or can't be one: loading, a failed month, and
    /// squad games that couldn't be read. None of them is drawn as an empty
    /// month.
    @ViewBuilder
    private var status: some View {
        if page.isLoading {
            statusLine("Loading…")
        }

        if let failure = page.failure {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                statusLine(failure)
                Button("Retry", action: onRetry)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprScoreboardLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if page.squadGamesFailed {
            statusLine("Couldn't load your squad's games.")
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .hooprType(.caption)
            .foregroundStyle(Color.hooprScoreboardDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The selected day, by name, under a hairline.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Rectangle()
                .fill(Color.hooprScoreboardDot)
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(page.dayTitles[selectedDay] ?? "")
                .hooprType(.label)
                .foregroundStyle(Color.hooprScoreboardText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The popup's geometry.
nonisolated enum RunCalendarPopupMetrics {
    /// The disc behind the X.
    static let closeDisc: CGFloat = 30
}

/// A day on fire: the LED orange at the top, `hooprScoreboardEmber` at the
/// foot — light orange to red on the dark screen, deep orange to deep red on
/// the pale one. Shared by the popup's zones, the tile's squares and the
/// legend.
struct FireZone: View {
    var body: some View {
        LinearGradient(
            colors: [Color.hooprScoreboardLabel, Color.hooprScoreboardEmber],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The popup grid's geometry, and the measurement that it holds at every text
/// size — so a day is never a target under 44pt, and its number always sits
/// inside its zone.
nonisolated enum RunCalendarMetrics {
    /// How far the grid reaches past the screen's text inset on each side.
    /// `Spacing.sm`, so a column is 47.7pt rather than 45.4 on the 402pt phone.
    static let gridBleed: CGFloat = Spacing.sm

    /// A day cell's least size, as a target.
    static let minimumTarget: CGFloat = 44

    /// The space around a zone inside its cell: half the gap between two
    /// zones, and the room the selection ring is drawn in.
    static let zoneInset: CGFloat = 3
    static let zoneCornerRadius: CGFloat = 8
    static let selectionLine: CGFloat = 2

    /// **The one cap in the calendar.** Seven zones of two-digit numbers
    /// can't be wider than the page: a zone is 41.7pt, and a bold "30" passes
    /// that from `.accessibility4`. 30pt is a step past `.accessibility3`, so the
    /// cap changes nothing below the top two sizes — a number spilling out of
    /// its zone is the worse of the two.
    static let dayNumberMaximumSize: CGFloat = 30

    static let dotDiameter: CGFloat = 5
    static let dotSpacing: CGFloat = 2
    /// Where the dots stop growing: three of them, and their gaps, inside the
    /// narrowest zone with a point to spare each side.
    static let maximumDotDiameter: CGFloat = 11

    static let underline: CGFloat = 2
    static let underlineGap: CGFloat = 1

    static let legendSwatch: CGFloat = 10

    /// How far a drag has to go before it can be a swipe.
    static let swipeDistance: CGFloat = 24

    /// A column's width: the popup's screen's text width — the popup is
    /// `contentWidth` wide, Home's content width, as it sits inside the page
    /// margins — plus the bleed on both sides, over seven.
    static func columnWidth(contentWidth: CGFloat = HomeHeroMetrics.contentWidth) -> CGFloat {
        (StatsScoreboardMetrics.innerWidth(cardWidth: contentWidth) + gridBleed * 2) / 7
    }

    /// A zone's width: its column, less the inset on each side.
    static func zoneWidth(contentWidth: CGFloat = HomeHeroMetrics.contentWidth) -> CGFloat {
        columnWidth(contentWidth: contentWidth) - zoneInset * 2
    }

    /// The widest a day number can be — today's, which is bold — at `category`.
    static func dayNumberWidth(at category: UIContentSizeCategory) -> CGFloat {
        let size = HooprFontMetrics.scaledSize(
            HooprTextRole.caption.size,
            maximumSize: dayNumberMaximumSize,
            at: category
        )
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return (1 ... 31)
            .map { ceil(("\($0)" as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    /// Whether the grid holds at `category`: every column a full target, and
    /// every day number inside its zone.
    static func fits(at category: UIContentSizeCategory, contentWidth: CGFloat = HomeHeroMetrics.contentWidth) -> Bool {
        columnWidth(contentWidth: contentWidth) >= minimumTarget
            && dayNumberWidth(at: category) <= zoneWidth(contentWidth: contentWidth)
    }
}
