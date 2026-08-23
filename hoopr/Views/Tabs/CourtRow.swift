import SwiftUI

/// One entry in the court list: name with its amenity badges beside it, a
/// metadata line beneath, and a star that toggles without leaving the list.
///
/// **Every row is the same height, deliberately.** The badges used to sit on
/// their own line below the metadata, so a court with amenities was a whole
/// line taller than one without and the list scrolled in uneven jumps. Moving
/// them alongside the name collapses the row to two lines for every court —
/// but that alone isn't enough, because a court with no badges at all would
/// still be a couple of points shorter. `badgeLineHeight` is what closes that
/// gap; see below.
struct CourtRow: View {
    let nearbyCourt: NearbyCourt
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    private var court: Court { nearbyCourt.court }

    /// The height of a badge capsule at the reader's text size — `CourtBadges`
    /// draws 11pt text with 4pt of padding above and below. The name line is
    /// held to at least this, so a court with no badges is exactly as tall as
    /// one with them.
    ///
    /// Scaled rather than a literal 21, because the badges themselves scale:
    /// a fixed floor would stop matching the moment the reader moves off the
    /// default text size, which is precisely when uneven rows are worst.
    /// `.caption2` is the style `Typography.swift` maps 11pt onto, so this
    /// tracks the badge's own curve rather than guessing at one.
    @ScaledMetric(relativeTo: .caption2) private var badgeLineHeight: CGFloat = 21

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // Widest arrangement that fits, in descending order. A long
                // name sheds badges rather than truncating: the badges are
                // facts you can still get by tapping through, the name is how
                // you know which court you're looking at. The last rung shows
                // no badges and lets the name truncate, which is the only
                // honest option left when even the bare name overruns.
                ViewThatFits(in: .horizontal) {
                    titleLine(badgeLimit: nil)
                    titleLine(badgeLimit: 2)
                    titleLine(badgeLimit: 1)
                    titleLine(badgeLimit: 0)
                }
                .frame(minHeight: badgeLineHeight, alignment: .leading)

                // City and distance on one line, not two. They're both "where
                // is this", they're both secondary, and stacking them gave a
                // row three lines of near-equal weight — which is what made a
                // list of twelve courts need a full screen.
                Text("\(court.city) · \(nearbyCourt.distanceText) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .hooprFont(17, maximumSize: 22)
                    .foregroundStyle(isFavorite ? Color.hooprOrange : Color.hooprSecondaryText)
                    // Widen the tap target without widening the icon, so the
                    // star doesn't swallow taps meant for the row.
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The name and its badges on one line. `badgeLimit` is what the
    /// `ViewThatFits` ladder above varies; `nil` means every badge.
    private func titleLine(badgeLimit: Int?) -> some View {
        HStack(spacing: 8) {
            // One line, never two. Wrapping would reintroduce exactly the
            // height variance this layout exists to remove.
            Text(court.displayName)
                .hooprFont(16, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(1)

            CourtBadges(court: court, limit: badgeLimit)
        }
    }
}
