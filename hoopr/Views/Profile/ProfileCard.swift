import SwiftUI

/// One tile in the profile's card mosaic: a symbol and a small label along the
/// top, the value anchored to the bottom, and an optional second line under it.
///
/// The card fills whatever frame it's given rather than sizing to its content —
/// that's what lets `ProfileView` interlock a tall card beside two short ones
/// and have the edges line up. Callers set a *floor* and let the card stretch;
/// see `ProfileView.grid` for why a fixed height is the wrong tool here.
///
/// Passing `onEdit: nil` renders a read-only card — used for values this app
/// doesn't own (`email`, managed by Firebase Auth), that are immutable by
/// design (`Date Joined`), or that are edited somewhere else entirely
/// (favourites, starred from the map). A read-only card isn't a button at all,
/// so there's no disabled state to style.
struct ProfileCard: View {
    /// How much weight the value carries. `.feature` is for the one card that
    /// leads the grid; everything else is a `.tile`.
    enum Prominence {
        case tile
        case feature

        var valueSize: CGFloat {
            switch self {
            case .tile:    17
            case .feature: 22
            }
        }

        var valueWeight: Font.Weight {
            switch self {
            case .tile:    .semibold
            case .feature: .bold
            }
        }

        /// How many lines the value may take before it starts shrinking. The
        /// feature card is tall enough to hold a wrapped court name.
        var valueLineLimit: Int {
            switch self {
            case .tile:    1
            case .feature: 2
            }
        }
    }

    let symbol: String
    let label: String
    let value: String?
    /// Shown in place of a missing value, in secondary colour.
    let placeholder: String
    /// A quieter second line under the value — a court's city, a unit.
    var detail: String?
    var prominence: Prominence = .tile
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) {
                card
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(value ?? placeholder)")
            .accessibilityHint("Double tap to edit")
        } else {
            card
                .accessibilityElement(children: .combine)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            head

            // Pushes the value to the bottom edge, so a one-line card and a
            // two-line card still share a baseline across a row.
            Spacer(minLength: 6)

            Text(value ?? placeholder)
                .hooprFont(prominence.valueSize, weight: prominence.valueWeight)
                .foregroundStyle(value == nil ? Color.hooprSecondaryText : Color.hooprPrimaryText)
                .lineLimit(prominence.valueLineLimit)
                // The mosaic's widths are fixed by the grid, so a long court
                // name shrinks rather than truncating.
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)

            if let detail {
                Text(detail)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)
            }

            // The feature card is tall enough that a bottom-anchored value
            // reads as bottom-heavy rather than as a baseline; centring it in
            // the space under the label is what a tile hasn't got room to do.
            if prominence == .feature {
                Spacer(minLength: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.hooprBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .hooprFont(11, weight: .semibold, maximumSize: 15)
                .foregroundStyle(Color.hooprOrange)

            Text(label.uppercased())
                .hooprFont(11, weight: .semibold, maximumSize: 15)
                .kerning(0.6)
                .foregroundStyle(Color.hooprSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            // The whole card is the tap target; this is the affordance saying
            // so, which is why it isn't a button in its own right.
            if onEdit != nil {
                Image(systemName: "square.and.pencil")
                    .hooprFont(13, weight: .medium, maximumSize: 17)
                    .foregroundStyle(Color.hooprOrange)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            ProfileCard(
                symbol: "basketball.fill",
                label: "Home Court",
                value: "Durham Central Park",
                placeholder: "Not set",
                detail: "Durham",
                prominence: .feature,
                onEdit: {}
            )
            .frame(minHeight: 172, maxHeight: .infinity)

            VStack(spacing: 12) {
                ProfileCard(
                    symbol: "star.fill",
                    label: "Favorites",
                    value: "12",
                    placeholder: "0",
                    detail: "courts"
                )
                .frame(minHeight: 80, maxHeight: .infinity)

                ProfileCard(
                    symbol: "location.circle.fill",
                    label: "Radius",
                    value: "5 mi",
                    placeholder: "5 mi",
                    detail: "around you",
                    onEdit: {}
                )
                .frame(minHeight: 80, maxHeight: .infinity)
            }
        }

        ProfileCard(
            symbol: "envelope.fill",
            label: "Email",
            value: "aeleot11@gmail.com",
            placeholder: "Not set"
        )
        .frame(minHeight: 80)
    }
    .padding(16)
    .background(Color.hooprBackground)
}
