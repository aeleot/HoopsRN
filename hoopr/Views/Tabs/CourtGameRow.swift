import SwiftUI

/// One entry in the **Now** segment: a court that has a run on today, shown by
/// its next run rather than by its amenities.
///
/// The sibling of `CourtRow`, and deliberately a different row. `CourtRow`
/// answers "what is this court like" — hoops, surface, lights. This answers
/// "can I play here in the next hour", so the tip-off time and whether there's
/// room take the space the badges had.
///
/// **One row per court, not per run.** The Runs tab lists individual games,
/// because each one needs its own Join/Leave button. This is a map entry point:
/// a court with three runs is one place to walk to and one tap target, so the
/// extra runs are summarised (`+2 more today`) and the row routes into the
/// detail card where the actions live.
///
/// Same uniform-height discipline as `CourtRow` — single-line name, a scaled
/// floor under the status line — because a list that scrolls in uneven jumps
/// was the exact problem that layout was written to fix.
struct CourtGameRow: View {
    let activeCourt: ActiveCourt

    private var court: Court { activeCourt.court }
    private var game: Game { activeCourt.leadGame }

    /// Matches `CourtRow.badgeLineHeight`: an 11pt capsule with 4pt of padding
    /// above and below. Keeps this row the same height as a court row when the
    /// two are seen back to back across a segment switch.
    @ScaledMetric(relativeTo: .caption2) private var statusLineHeight: CGFloat = 21

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(court.displayName)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)

                Text(metaText)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Time over status, one trailing column. "When" is the question a
            // scan answers first — the spot count only matters once the time
            // already works for you — and lining the clock up with the court
            // name's own first line reads as one row instead of two.
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeText)
                    .hooprFont(13, weight: .semibold, maximumSize: 18)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .monospacedDigit()
                    .lineLimit(1)

                statusPill
            }
            .frame(minHeight: statusLineHeight, alignment: .trailing)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to see this court")
    }

    /// Just the clock time. The date would be noise — everything in this
    /// segment is today by construction.
    private var timeText: String {
        Self.timeFormatter.string(from: game.scheduledTime)
    }

    private var metaText: String {
        let base = "\(court.city) · \(activeCourt.distanceText)"
        guard let more = activeCourt.additionalGamesText else { return base }
        return "\(base) · \(more)"
    }

    @ViewBuilder
    private var statusPill: some View {
        let status = Self.status(openSlots: game.openSlots)

        Text(status.text)
            .hooprFont(11, weight: .bold, maximumSize: 15)
            .lineLimit(1)
            .foregroundStyle(status.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(status.background))
    }

    /// Room first, because that's the decision the reader is making.
    ///
    /// **Both pairings are ones `ThemeContrastTests` already proves.** The
    /// joinable state is `hooprOnBrand` on a filled `hooprOrange` capsule —
    /// the primary-button pairing, asserted at 6.61:1 light and 7.15:1 dark.
    /// It is deliberately *not* orange text on a 12%-orange tint, which is how
    /// `GameCard` draws its own badges: `hooprOrange` as a foreground measures
    /// 2.34:1 on `hooprFill` in light mode, a defect `GAPS.md` already tracks,
    /// and 11pt bold is normal text by WCAG's reckoning rather than large.
    /// A new surface shouldn't add an instance of a known failure.
    ///
    /// Full is secondary text on fill, not a red: a full run isn't an error,
    /// and `hooprRed` is reserved for things that went wrong.
    private static func status(
        openSlots: Int
    ) -> (text: String, foreground: Color, background: Color) {
        guard openSlots > 0 else {
            return ("FULL", Color.hooprSecondaryText, Color.hooprFill)
        }
        return (
            openSlots == 1 ? "1 SPOT" : "\(openSlots) SPOTS",
            Color.hooprOnBrand,
            Color.hooprOrange
        )
    }

    private var accessibilityText: String {
        let status = Self.status(openSlots: game.openSlots)
        return "\(court.displayName), \(metaText), \(timeText), \(status.text.lowercased())"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
