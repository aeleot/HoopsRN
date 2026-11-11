import SwiftUI
import UIKit

/// The run calendar's way in: a tile beside Home's scoreboard, as tall as the
/// scoreboard, drawing this month in miniature — a square for every day, lit
/// the way the month popup lights it (2026-10-06, the user's design). Tapping
/// it opens the month (`RunCalendarPopup`).
///
/// **A month of squares, not a date.** It first showed today's date over the
/// month's name, like a calendar icon; beside the scoreboard's numbers a big
/// "5" read as a sixth stat. A grid of days can only be a calendar, and it
/// says what is in it before it is opened: orange for a day with a run, a day
/// on fire for three or more (`FireZone`), your squad's colour for a match
/// (`hooprScoreboardSquad`). Today is outlined.
///
/// **On the scoreboard's own screen** (`ScoreboardHousing`), so the row reads
/// as one instrument: lit squares on the unlit LEDs. Every lit colour stands off
/// the screen at 3:1 (`ThemeContrastTests`). VoiceOver reads the tile as one
/// button that says what the month holds.
struct RunCalendarTile: View {
    let tile: RunCalendarViewModel.Tile
    /// Stretched to the height of the scoreboard beside it.
    var fillsHeight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ScoreboardHousing(fillsHeight: fillsHeight) {
                // Top-left, as every panel's label is on the scoreboard beside
                // it (the user's call) — same role, same spacing, same line.
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "calendar")
                        Text(tile.monthAbbreviation)
                    }
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprScoreboardLabel)
                    .lineLimit(1)

                    month
                }
                .fixedSize()
            }
        }
        .buttonStyle(.hooprPress)
        .accessibilityLabel(tile.spoken)
        .accessibilityHint("Opens the month")
    }

    private var month: some View {
        VStack(spacing: RunCalendarTileMetrics.gap) {
            ForEach(Array(tile.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: RunCalendarTileMetrics.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        square(day)
                            .frame(width: RunCalendarTileMetrics.square, height: RunCalendarTileMetrics.square)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func square(_ day: Int?) -> some View {
        if let day {
            let mark = tile.marks[day] ?? RunCalendarViewModel.DayMark()
            let shape = RoundedRectangle(cornerRadius: RunCalendarTileMetrics.cornerRadius, style: .continuous)

            Group {
                switch mark.zone {
                case .squad:
                    Color.hooprScoreboardSquad(tile.squadColorKey ?? Squad.defaultColorKey)
                case .fire:
                    FireZone()
                case .plain:
                    mark.runCount > 0 ? Color.hooprScoreboardLabel : Color.hooprScoreboardDot
                }
            }
            .clipShape(shape)
            .overlay {
                if day == tile.today {
                    shape.strokeBorder(Color.hooprScoreboardText, lineWidth: RunCalendarTileMetrics.todayLine)
                }
            }
        } else {
            Color.clear
        }
    }
}

/// The tile's geometry.
nonisolated enum RunCalendarTileMetrics {
    /// About the scoreboard's height at the default text size, so beside it the
    /// tile reads as a square. 132 since 2026-10-06 (the user's call: at 112 the
    /// month was cramped), and the scoreboard gave up the 20.
    static let width: CGFloat = 132

    /// A day's square and the gap between squares: seven of each across fill
    /// the tile's screen exactly — 132pt less the bezel and the screen's
    /// padding is 88, and 7 × 10 + 6 × 3 is 88. Fixed, not scaled with the
    /// text: the squares carry no text, and the label above them is capped.
    static let square: CGFloat = 10
    static let gap: CGFloat = 3
    static let cornerRadius: CGFloat = 2
    static let todayLine: CGFloat = 1
}
