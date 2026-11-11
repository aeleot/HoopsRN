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

    /// One chip: what it says, and whether it's a feature of the court, a
    /// notice about when you may use it, or a caution that you may not get on.
    struct Amenity: Equatable {
        enum Kind: Equatable {
            /// What the court *has* — hoops, lights, surface.
            case feature
            /// When it may not be available. A school court is normally
            /// playable after hours, so this is a caveat, not a warning.
            case notice
            /// That you may not get on it at all.
            case caution
        }

        let text: String
        let kind: Kind

        var isCaution: Bool { kind == .caution }

        /// Anything that isn't a feature. **Never the chip that gets dropped**
        /// when a row is short of room — see `amenities(for:limit:)`.
        var isWarning: Bool { kind != .feature }

        /// What VoiceOver says. The chip's own word is too short to carry the
        /// caveat ("School" alone reads as a fact about the building).
        var spoken: String {
            switch kind {
            case .feature: return text
            case .notice:  return "\(text) court, may be closed during school hours"
            case .caution: return "\(text) access, you may not be able to play here"
            }
        }
    }

    /// The chips for `court`, in display order: features first, then the one
    /// thing that says you may not be able to play — at most one of a school
    /// notice or a restricted caution, since a court is one or the other.
    ///
    /// "Restricted" and "School" are the odd ones out: every other label tells
    /// you what the court *has*, while these tell you about getting on it. They
    /// read identically to "Lit" and "Covered" before, which is the one thing on
    /// this row a player needs to notice.
    static func amenities(for court: Court) -> [Amenity] {
        var result: [Amenity] = []
        if let hoops = court.hoops {
            result.append(Amenity(text: hoops == 1 ? "1 hoop" : "\(hoops) hoops", kind: .feature))
        }
        if court.isLit == true {
            result.append(Amenity(text: "Lit", kind: .feature))
        }
        if court.isCovered == true {
            result.append(Amenity(text: "Covered", kind: .feature))
        }
        if let surface = court.surface {
            result.append(Amenity(text: surface.capitalized, kind: .feature))
        }
        switch court.access {
        case .school:     result.append(Amenity(text: "School", kind: .notice))
        case .restricted: result.append(Amenity(text: "Restricted", kind: .caution))
        case .public:     break
        }
        return result
    }

    /// The badges to draw, narrowed to `limit` if one is set.
    ///
    /// **A warning is never the one dropped.** `amenities(for:)` emits it
    /// *last* because that's where it reads best when everything is shown, so a
    /// plain `prefix` would shed the single chip a player most needs — the one
    /// saying they may not get on this court, or not always. Warnings are
    /// therefore kept first and the remaining slots filled with features, then
    /// the result is re-emitted in the original order so the row and the detail
    /// card still read the same way round.
    static func amenities(for court: Court, limit: Int?) -> [Amenity] {
        let all = amenities(for: court)
        guard let limit, all.count > limit else { return all }
        guard limit > 0 else { return [] }

        let warnings = all.filter(\.isWarning)
        let features = all.filter { !$0.isWarning }
        let kept = Set(
            warnings.map(\.text) + features.prefix(max(0, limit - warnings.count)).map(\.text)
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
                        .padding(.horizontal, Spacing.Pill.horizontal)
                        .padding(.vertical, Spacing.Pill.vertical)
                        // The two warnings are outlined rather than filled, so
                        // their text lands on the card ground rather than on
                        // `hooprFill`, where the red is at its tightest —
                        // 6.15:1 light, 4.94:1 dark. Both clear AA today, so
                        // this is headroom rather than a fix: on the surface
                        // behind it the same red reads 6.71:1 / 6.03:1. A
                        // notice takes the strong separator's edge and
                        // secondary text (a pairing already asserted) — drawn
                        // apart from the features without shouting like red.
                        .background(amenity.isWarning ? Color.clear : Color.hooprFill)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Self.edge(for: amenity.kind), lineWidth: 1)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(amenity.spoken)
                }
            }
        }
    }

    private static func edge(for kind: Amenity.Kind) -> Color {
        switch kind {
        case .feature: return .clear
        case .notice:  return .hooprSeparatorStrong
        case .caution: return Color.hooprRed.opacity(0.45)
        }
    }
}
