import SwiftUI

/// One entry in the court list: name and a metadata line on the left, amenity
/// badges beneath, and a star that toggles without leaving the list.
struct CourtRow: View {
    let nearbyCourt: NearbyCourt
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    private var court: Court { nearbyCourt.court }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(court.displayName)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // City and distance on one line, not two. They're both "where
                // is this", they're both secondary, and stacking them gave a
                // row three lines of near-equal weight — which is what made a
                // list of twelve courts need a full screen.
                Text("\(court.city) · \(nearbyCourt.distanceText) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)

                CourtBadges(court: court)
                    .padding(.top, 3)
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
}
