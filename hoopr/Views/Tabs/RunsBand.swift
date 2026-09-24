import SwiftUI

/// The Runs band's hero: the week, one column a day, with a dot for every run
/// on it (redesigned 2026-09-23, at the user's request — the band was "very
/// plain, very grey", and its header "does not make sense").
///
/// It answers the tab's question the way a calendar does rather than in
/// copy: *when are the runs, and which am I in?* Today leads, in an orange
/// disc. A run you're on is a **filled** accent dot, one you could join is a
/// **ring** — a shape difference as well as a colour one, so the two read
/// apart without colour. A day with runs is a button that scrolls the board
/// to that day's heading; a day without is quiet and inert.
struct RunsWeekStrip: View {
    let days: [LocalRunsViewModel.DaySummary]
    let onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                column(day, isToday: index == 0)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func column(_ day: LocalRunsViewModel.DaySummary, isToday: Bool) -> some View {
        Button {
            onSelect(day.day)
        } label: {
            VStack(spacing: Spacing.xs) {
                Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                    .hooprType(.label)
                    .foregroundStyle(isToday ? Color.hooprBrandAccent : Color.hooprSecondaryText)
                    .lineLimit(1)

                dayNumber(day, isToday: isToday)

                RunDots(total: day.total, yours: day.yours)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hooprPress)
        .disabled(day.total == 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(day, isToday: isToday))
        .accessibilityHint(day.total > 0 ? "Shows that day's runs" : "")
    }

    /// Capped: seven columns share the width, and a column can't grow.
    @ViewBuilder
    private func dayNumber(_ day: LocalRunsViewModel.DaySummary, isToday: Bool) -> some View {
        let number = Text(day.day.formatted(.dateTime.day()))
            .hooprFont(17, weight: .semibold, maximumSize: 22)
            .monospacedDigit()
            .lineLimit(1)

        if isToday {
            number
                .foregroundStyle(Color.hooprOnBrand)
                .frame(width: Self.discSize, height: Self.discSize)
                .background(Circle().fill(Color.hooprOrange))
        } else {
            number
                .foregroundStyle(day.total > 0 ? Color.hooprPrimaryText : Color.hooprSecondaryText)
                .frame(width: Self.discSize, height: Self.discSize)
        }
    }

    /// Room for a capped two-digit day at the largest text size.
    static let discSize: CGFloat = 36

    /// "Today, Wednesday, September 23: 3 runs, you're in 3."
    nonisolated static func spoken(_ day: LocalRunsViewModel.DaySummary, isToday: Bool) -> String {
        let date = day.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let prefix = isToday ? "Today, \(date)" : date
        guard day.total > 0 else { return "\(prefix): no runs" }
        let runs = day.total == 1 ? "1 run" : "\(day.total) runs"
        return day.yours > 0 ? "\(prefix): \(runs), you're in \(day.yours)" : "\(prefix): \(runs)"
    }
}

/// A day's runs as dots: yours filled in the accent, the rest as rings, at
/// most three and then a "+". Fixed-size marks, like `FormDot`.
struct RunDots: View {
    let total: Int
    let yours: Int

    static let diameter: CGFloat = 6
    static let limit = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(total, Self.limit), id: \.self) { index in
                if index < yours {
                    Circle()
                        .fill(Color.hooprBrandAccent)
                        .frame(width: Self.diameter, height: Self.diameter)
                } else {
                    Circle()
                        .strokeBorder(Color.hooprSecondaryText, lineWidth: 1.5)
                        .frame(width: Self.diameter, height: Self.diameter)
                }
            }
            if total > Self.limit {
                Text("+")
                    .hooprFont(10, weight: .bold, maximumSize: 12)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        // Holds the row's height on a day with no runs, so the columns line up.
        .frame(height: Self.diameter + 4)
        .accessibilityHidden(true)
    }
}

/// One fact on the band: a glyph, a number, what it counts — the same shape
/// Home's detail line uses, so the two bands read alike.
struct RunsBandStat: View {
    let symbol: String
    let value: String?
    let unit: String
    let spoken: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .hooprType(.caption)
                .foregroundStyle(Color.hooprBrandAccent)

            if let value {
                Text(value)
                    .hooprType(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.hooprPrimaryText)
            }

            Text(unit)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// The court, enlarged and half off the band's trailing edge — Runs' emblem,
/// as the ball is Home's: the left half of a court seen from above, its
/// three-point arc and key in view. Drawn in `hooprBrandWatermark`, so what
/// crosses it — the strip's later days, the profile button — reads as it
/// does on a pressed row (`ThemeContrastTests`).
///
/// Decorative: hidden from VoiceOver, and it never takes a touch.
struct RunsBandCourt: View {
    private static let tilt: Angle = .degrees(-12)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 2 / 3

            Image.court
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.hooprBrandWatermark)
                .rotationEffect(Self.tilt)
                .frame(width: width)
                .position(x: proxy.size.width, y: proxy.size.height * 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
