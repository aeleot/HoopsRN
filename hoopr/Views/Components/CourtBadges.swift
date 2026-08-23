import SwiftUI

/// The amenity chips for a court — hoops, lights, surface, access.
///
/// Shared by the list row and the map's detail card so a court reads the same
/// in both places. Previously the row owned this and the card showed nothing,
/// which meant tapping a court to learn more about it told you *less* than the
/// row you tapped it from.
struct CourtBadges: View {
    let court: Court

    /// Draw at most this many badges, or all of them when `nil` (the default,
    /// and what the detail card wants — it has a line to itself).
    ///
    /// `CourtRow` sets it through a `ViewThatFits` ladder so a row sheds its
    /// least-important badges rather than truncating the court's name. Dropping
    /// a badge costs the reader a fact they can still get by tapping through;
    /// crushing "Bethesda Park" to "Beth…" costs them the one thing that tells
    /// them which court the row even is.
    var limit: Int?

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

    /// The badges to draw, narrowed to `limit` if one is set.
    ///
    /// **A caution is never the one dropped.** `amenities(for:)` emits
    /// "Restricted" *last* because that's where it reads best when everything
    /// is shown, so a plain `prefix` would shed the single badge a player most
    /// needs to see — the one saying they may not get on this court at all.
    /// Cautions are therefore kept first and the remaining slots filled with
    /// features, then the result is re-emitted in the original order so the
    /// row and the detail card still read the same way round.
    static func amenities(for court: Court, limit: Int?) -> [(text: String, isCaution: Bool)] {
        let all = amenities(for: court)
        guard let limit, all.count > limit else { return all }
        guard limit > 0 else { return [] }

        let cautions = all.filter(\.isCaution)
        let features = all.filter { !$0.isCaution }
        let kept = Set(
            cautions.map(\.text) + features.prefix(max(0, limit - cautions.count)).map(\.text)
        )
        return all.filter { kept.contains($0.text) }
    }

    var body: some View {
        let amenities = Self.amenities(for: court, limit: limit)

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
                        // The caution badge is outlined rather than filled so
                        // its text lands on the card ground rather than on
                        // `hooprFill`, where the red is at its tightest —
                        // 6.15:1 light, 4.94:1 dark. Both clear AA today, so
                        // this is headroom rather than a fix: on the surface
                        // behind it the same red reads 6.71:1 / 6.03:1.
                        // (A "4.05:1, under AA" figure stood here until
                        // 2026-08-21; it measured the reverted palette's red.)
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
