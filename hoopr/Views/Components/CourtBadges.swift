import SwiftUI

/// The amenity chips for a court — hoops, lights, surface, access.
///
/// Shared by the list row and the map's detail card so a court reads the same
/// in both places. Previously the row owned this and the card showed nothing,
/// which meant tapping a court to learn more about it told you *less* than the
/// row you tapped it from.
struct CourtBadges: View {
    let court: Court

    /// Only facts the dataset actually carries. Absent OSM tags mean unknown,
    /// so nothing is inferred and no placeholder badge is shown.
    static func labels(for court: Court) -> [String] {
        amenities(for: court).map(\.text)
    }

    /// A badge and whether it's a caution rather than a feature.
    ///
    /// "Restricted" is the odd one out: every other label tells you what the
    /// court *has*, while that one tells you that you may not get on it. It
    /// read identically to "Lit" and "Covered" before, which is the one thing
    /// on this row a player needs to notice.
    static func amenities(for court: Court) -> [(text: String, isCaution: Bool)] {
        var result: [(text: String, isCaution: Bool)] = []
        if let hoops = court.hoops {
            result.append((hoops == 1 ? "1 hoop" : "\(hoops) hoops", false))
        }
        if court.isLit == true {
            result.append(("Lit", false))
        }
        if court.isCovered == true {
            result.append(("Covered", false))
        }
        if let surface = court.surface {
            result.append((surface.capitalized, false))
        }
        if court.access == .restricted {
            result.append(("Restricted", true))
        }
        return result
    }

    var body: some View {
        let amenities = Self.amenities(for: court)

        if !amenities.isEmpty {
            HStack(spacing: 6) {
                ForEach(amenities, id: \.text) { amenity in
                    Text(amenity.text)
                        .hooprFont(11, weight: .medium)
                        .foregroundStyle(
                            amenity.isCaution ? Color.hooprRed : Color.hooprSecondaryText
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // The caution badge is outlined rather than filled: on
                        // `hooprFill` the red lands at 4.05:1 in dark mode,
                        // under AA, while on the card ground behind it the same
                        // red clears in both appearances.
                        .background(amenity.isCaution ? Color.clear : Color.hooprFill)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    amenity.isCaution
                                        ? Color.hooprRed.opacity(0.45)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
            }
        }
    }
}
