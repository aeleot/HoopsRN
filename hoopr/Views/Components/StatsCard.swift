import SwiftUI
import UIKit

/// Home's participation summary: runs played, weekly streak, last run.
///
/// **Restored as a card on 2026-09-22, after the redesign had cut it to one
/// grey sentence.** UI revamp Phase 2b demoted it to a caption line at the
/// bottom of Home, on the reasoning that these are self-reported counters and
/// must not look as authoritative as a squad's confirmed record. The second
/// half of that still holds; the first half overshot. The card's product
/// intent was always "a minimal card" that surfaces engagement —
/// and a bare sentence read to the user as a feature that had broken or not
/// been finished. So it is a card again, with its icons back, and the
/// authority line is held by *type tier* instead of by hiding it: the values
/// are row-tier `headline`, never the `numeral` / `display` tier that the hero
/// and confirmed squad records use.
///
/// **It can no longer break mid-word, and the reason is the layout rather than
/// a cap.** The old card gave each stat an equal third of the width. At the
/// default text size that is 93pt, and "Yesterday" needs 92; one size up it
/// needs 116, so it broke — "Last / Run", "Ru / ns". Now the columns hug
/// their content and
/// `ViewThatFits` switches the whole card to a stack only when the row
/// genuinely doesn't fit, which `StatsCardMetrics` measures and
/// `HomeHeroMetricsTests` pins: a row through `.xxxLarge`, a stack from
/// `.accessibility1`.
struct StatsCard: View {
    let completedCount: Int
    let participationStreak: Int
    let lastCompletedText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // The three side by side, the gaps between them flexing so the
            // columns keep their own widths. A divider sits in each gap.
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    if index > 0 {
                        Spacer(minLength: Spacing.md)
                        Divider().overlay(Color.hooprBorder)
                        Spacer(minLength: Spacing.md)
                    }
                    item(stat)
                }
            }

            // Out of room: one stat per row, each with the card's full width.
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    if index > 0 {
                        Divider().overlay(Color.hooprBorder)
                    }
                    item(stat)
                }
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your stats")
    }

    // MARK: - The three stats

    struct Stat {
        let symbol: String
        let label: String
        let value: String
        /// What VoiceOver says. "1 wk" is read as letters; "1 week" isn't.
        let spoken: String
    }

    var stats: [Stat] {
        [
            Stat(
                symbol: "basketball.fill",
                label: "Runs",
                value: "\(completedCount)",
                spoken: completedCount == 1 ? "1 run" : "\(completedCount) runs"
            ),
            Stat(
                symbol: "flame.fill",
                label: "Streak",
                value: Self.streakText(weeks: participationStreak),
                spoken: Self.spokenStreak(weeks: participationStreak)
            ),
            Stat(
                symbol: "clock.fill",
                label: "Last Run",
                value: lastCompletedText,
                spoken: "last run \(lastCompletedText.lowercased())"
            ),
        ]
    }

    /// "1 wk", "3 wks". The old card said "1 wks".
    nonisolated static func streakText(weeks: Int) -> String {
        weeks == 1 ? "1 wk" : "\(weeks) wks"
    }

    nonisolated static func spokenStreak(weeks: Int) -> String {
        weeks == 1 ? "1 week streak" : "\(weeks) week streak"
    }

    private func item(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 5) {
                Image(systemName: stat.symbol)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprBrandAccent)

                Text(stat.label)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Text(stat.value)
                .hooprType(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.spoken)
    }
}

/// The arithmetic behind the card's row-or-stack choice, so it can be pinned in
/// a test rather than trusted to a screenshot at one text size.
///
/// It mirrors what `ViewThatFits` asks of the row: the sum of every column's
/// ideal width, the minimum gaps and the dividers, against the width the card
/// is given. Measured with the same fonts the roles resolve to.
nonisolated enum StatsCardMetrics {
    /// Home's content width less the card's own padding.
    static let innerWidth: CGFloat = HomeHeroMetrics.contentWidth - Spacing.cardPadding * 2

    /// The widest values each column realistically holds.
    static let worstCase: [(label: String, value: String)] = [
        ("Runs", "128"),
        ("Streak", "12 wks"),
        ("Last Run", "Yesterday"),
    ]

    /// How wide the row needs to be at `category` to hold the worst case
    /// without wrapping anything.
    static func rowWidth(at category: UIContentSizeCategory) -> CGFloat {
        let columns = worstCase.map { column in
            let iconAndLabel = width(of: "M", role: .caption, at: category) + 5
                + width(of: column.label, role: .caption, at: category)
            return max(iconAndLabel, width(of: column.value, role: .headline, at: category))
        }
        let gaps = CGFloat(worstCase.count - 1) * (Spacing.md * 2 + 1)
        return columns.reduce(0, +) + gaps
    }

    static func width(of text: String, role: HooprTextRole, at category: UIContentSizeCategory) -> CGFloat {
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let font = UIFont.systemFont(ofSize: size, weight: role.uiFontWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
