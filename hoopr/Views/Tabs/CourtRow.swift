import SwiftUI

/// One entry in the court list: name, city and distance on the left, amenity
/// badges beneath, and a star that toggles without leaving the list.
struct CourtRow: View {
    let nearbyCourt: NearbyCourt
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    private var court: Court { nearbyCourt.court }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(court.name)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(court.city)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)

                Text("\(nearbyCourt.distanceText) away")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .hooprFont(11, weight: .medium)
                                .foregroundStyle(Color.hooprSecondaryText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.hooprFill)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .padding(.top, 3)
                }
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

    /// Only facts the dataset actually carries. Absent OSM tags mean unknown,
    /// so nothing is inferred and no placeholder badge is shown.
    private var badges: [String] {
        var result: [String] = []
        if let hoops = court.hoops {
            result.append(hoops == 1 ? "1 hoop" : "\(hoops) hoops")
        }
        if court.isLit == true {
            result.append("Lit")
        }
        if let surface = court.surface {
            result.append(surface.capitalized)
        }
        if court.access == .restricted {
            result.append("Restricted")
        }
        return result
    }
}
