import SwiftUI

/// One field of the profile, as a full-width row: a symbol in a tinted square
/// on the left, the field's label over its value, and a chevron when the row
/// leads somewhere.
///
/// Replaces the `ProfileCard` mosaic this screen used to stack. The mosaic sized
/// every card to its slot and made the page a puzzle of interlocking heights —
/// which meant a card's *height* carried meaning its content didn't, and a long
/// court name had to shrink to fit a tile rather than simply being read. A row
/// is the opposite trade: one column, one field per line, values free to run the
/// width of the screen.
///
/// **Every row is the same height, and none of them states one.** The height
/// comes from a label over a single line of value, so it moves with the
/// reader's text size and every row moves with it together. A value too long
/// for the width truncates with an ellipsis rather than wrapping — one long
/// court name shouldn't make its row taller than the five around it, and the
/// full text is on the screen the row opens anyway.
///
/// Passing `onTap: nil` renders a read-only row — used for values this app
/// doesn't own (`email`, managed by Firebase Auth), that are immutable by design
/// (`Joined`), or that are edited somewhere else entirely (favourites, starred
/// from the map). A read-only row isn't a button at all, so there's no disabled
/// state to style.
struct ProfileRow: View {
    let symbol: String
    let label: String
    let value: String?
    /// Shown in place of a missing value, in secondary colour.
    let placeholder: String
    /// A quieter trailing fragment on the value line — a court's city. Set off
    /// with a middot rather than given a line of its own, so a row with one
    /// stays the same height as a row without.
    var detail: String?
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label), \(value ?? placeholder)")
                .accessibilityHint("Double tap to edit")
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
            ProfileRowIcon(symbol: symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .hooprFont(12, weight: .semibold)
                    .kerning(0.3)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)

                valueLine
            }

            Spacer(minLength: 8)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .hooprFont(13, weight: .semibold, maximumSize: 17)
                    .foregroundStyle(Color.hooprSecondaryText.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileRowChrome()
    }

    /// The value and its detail on one line, with the detail dropped whole
    /// rather than truncated alongside it.
    ///
    /// `ViewThatFits` is doing real work here: laid out as a plain `HStack`,
    /// a court name too long for the row leaves the city a few points of width
    /// and both halves end in an ellipsis. Offering the pair first and the bare
    /// value second means a wide row gets "Bethesda Park · Durham" and a narrow
    /// one gets one cleanly truncated name — a truncated court name is a worse
    /// row than a missing city, and two ellipses are worse than either.
    private var valueLine: some View {
        ViewThatFits(in: .horizontal) {
            if let detail, value != nil {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    valueText
                    Text("· \(detail)")
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .lineLimit(1)
                }
            }

            valueText
        }
    }

    private var valueText: some View {
        Text(value ?? placeholder)
            .hooprFont(16, weight: .semibold)
            .foregroundStyle(value == nil ? Color.hooprSecondaryText : Color.hooprPrimaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A row that performs something rather than showing something — sign out. Same
/// chrome and the same left-hand square as `ProfileRow`, so the end of the list
/// doesn't change shape, with the tint carrying the meaning instead of a value.
struct ProfileActionRow: View {
    let symbol: String
    let title: String
    var tint: Color = .hooprOrange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ProfileRowIcon(symbol: symbol, tint: tint)

                Text(title)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .profileRowChrome()
        }
        .buttonStyle(.plain)
    }
}

/// The tinted square every row leads with. Fixed size on purpose — like
/// `PlayerAvatar`, the glyph is a fraction of a shape, so scaling it with the
/// reader's text size would push it past its own container. The text beside it
/// still scales, and the row grows to match.
private struct ProfileRowIcon: View {
    let symbol: String
    var tint: Color = .hooprOrange

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}

private extension View {
    /// The card the app draws everywhere — `hooprSurface`, a 1pt `hooprBorder`,
    /// the same 6% shadow `FriendRow` and `GameCard` carry. Shared by both row
    /// kinds so a tappable row and an action row can't drift apart.
    func profileRowChrome() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.hooprSurface)
                    .shadow(color: Color.hooprShadow(opacity: 0.06), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.hooprBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 10) {
        ProfileRow(
            symbol: "basketball.fill",
            label: "Home Court",
            value: "Durham Central Park",
            placeholder: "Not set",
            detail: "Durham",
            onTap: {}
        )

        ProfileRow(
            symbol: "star.fill",
            label: "Favorites",
            value: "12 courts",
            placeholder: "None yet"
        )

        ProfileRow(
            symbol: "envelope.fill",
            label: "Email",
            value: "aeleot11@gmail.com",
            placeholder: "Not set"
        )

        ProfileActionRow(
            symbol: "rectangle.portrait.and.arrow.right",
            title: "Sign Out",
            tint: .hooprRed
        ) {}
    }
    .padding(16)
    .background(Color.hooprBackground)
}
