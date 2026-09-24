import SwiftUI

/// One field of the profile, as a row on the page: a symbol, the field's label
/// over its value, and a chevron when the row leads somewhere.
///
/// Replaces the `ProfileCard` mosaic this screen used to stack. The mosaic sized
/// every card to its slot and made the page a puzzle of interlocking heights —
/// which meant a card's *height* carried meaning its content didn't, and a long
/// court name had to shrink to fit a tile rather than simply being read. A row
/// is the opposite trade: one column, one field per line, values free to run the
/// width of the screen.
///
/// **A row, not a card (UI revamp Phase 2b).** The
/// row fixed the mosaic and kept the card: every field had its own
/// `profileRowChrome()` *and* a tinted icon tile, which made the profile the
/// boxiest screen in the app — 7 panels and 14 shapes in one screenful. Now the
/// rows sit on the page, separated by hairlines (`DividedRows`), and the symbol
/// is a plain mark in the secondary colour.
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

    /// Where a `DividedRows` hairline should start so it runs under the text,
    /// not the symbol: the symbol's column plus the gap after it.
    static let textInset: CGFloat = ProfileRowSymbol.width + 14

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
            ProfileRowSymbol(symbol: symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)

                valueLine
            }

            Spacer(minLength: 8)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .hooprFont(13, weight: .semibold, maximumSize: 17)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .lineLimit(1)
                }
            }

            valueText
        }
    }

    private var valueText: some View {
        Text(value ?? placeholder)
            .hooprType(.subhead)
            .foregroundStyle(value == nil ? Color.hooprSecondaryText : Color.hooprPrimaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// What a profile row's mark is drawn in.
///
/// The brand case is the ordinary row's secondary mark — quiet, since there
/// are eight of them on one screen and none is more important than its label.
/// `destructive` is `hooprRed`, which reads on the page in both appearances.
enum ProfileRowTint {
    case brand
    case destructive

    var mark: Color {
        switch self {
        case .brand:       Color.hooprSecondaryText
        case .destructive: Color.hooprRed
        }
    }
}

/// A row that performs something rather than showing something — sign out. The
/// same symbol column as `ProfileRow`, so the end of the list doesn't change
/// shape, with the tint carrying the meaning instead of a value.
struct ProfileActionRow: View {
    let symbol: String
    let title: String
    var tint: ProfileRowTint = .brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ProfileRowSymbol(symbol: symbol, tint: tint)

                Text(title)
                    .hooprType(.subhead)
                    .foregroundStyle(tint.mark)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The mark every row leads with, in a fixed-width column so the labels line
/// up. It scales with the reader's text size up to a cap that still fits the
/// column; the tinted tile it used to sit in is gone.
struct ProfileRowSymbol: View {
    static let width: CGFloat = 28

    let symbol: String
    var tint: ProfileRowTint = .brand

    var body: some View {
        Image(systemName: symbol)
            .hooprFont(17, weight: .semibold, maximumSize: 24)
            .foregroundStyle(tint.mark)
            .frame(width: Self.width)
            .accessibilityHidden(true)
    }
}

#Preview {
    DividedRows(leadingInset: ProfileRow.textInset) {
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
            value: "player@example.com",
            placeholder: "Not set"
        )

        ProfileActionRow(
            symbol: "rectangle.portrait.and.arrow.right",
            title: "Sign Out",
            tint: .destructive
        ) {}
    }
    .padding(20)
    .background(Color.hooprBackground)
}
