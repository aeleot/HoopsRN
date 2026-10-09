import SwiftUI

/// One thing in the inbox, as a card: what kind of thing it is, who or what
/// it's about, and whatever it asks of you.
///
/// **Cards, not sectioned rows** (2026-09-28, at the user's request). The inbox
/// used to be titled sections — Matches, Requests, Squad invites, Sent — each a
/// `DividedRows` list under its own count, so a single friend request came with
/// an empty "Sent" section and three headers' worth of scaffolding around it.
/// Now it's one feed, and each card says what it is in its eyebrow line, so no
/// header has to.
///
/// Every kind shares this chrome — the card recipe, a 44pt leading visual, the
/// eyebrow, a title over an optional detail line — so a match, a request and an
/// invite read as the same kind of object. What differs is passed in: the
/// leading view, the actions row, and whether the card opens something
/// (`onOpen`, drawn with a chevron) or can be cleared (`onDismiss`, an ×).
struct InboxCard<Leading: View, Actions: View>: View {
    /// The leading visual's column — an avatar, a crest, a glyph.
    static var leadingColumn: CGFloat { PlayerAvatar.Size.row }

    /// Where the title starts, so the actions row lines up under it.
    static var textInset: CGFloat { leadingColumn + Spacing.md }

    /// "Friend request", "Squad invite" — uppercased by the `label` role.
    let eyebrow: String
    let symbol: String
    var tint: Color = .hooprBrandAccent

    let title: String
    var detail: String?
    var detailTint: Color = .hooprSecondaryText

    /// Opens what the card is about. The identity half is the target; the
    /// actions keep their own.
    var onOpen: (() -> Void)?
    var openHint: String?

    /// Clears a card that asks nothing of you.
    var onDismiss: (() -> Void)?

    @ViewBuilder let leading: Leading
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                identity

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .hooprType(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -Spacing.md)
                    .accessibilityLabel("Dismiss")
                }
            }

            // `EmptyView` still counts as a child of the stack, so an actions-
            // free card would carry the spacing under nothing without this.
            if Actions.self != EmptyView.self {
                HStack(spacing: Spacing.sm) {
                    actions
                }
                .padding(.leading, Self.textInset)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    @ViewBuilder
    private var identity: some View {
        if let onOpen {
            Button(action: onOpen) {
                HStack(spacing: Spacing.md) {
                    identityContent

                    // The × takes the trailing slot on a dismissible card; a
                    // chevron beside it made two controls out of one edge.
                    if onDismiss == nil {
                        Image(systemName: "chevron.right")
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(openHint ?? "")
        } else {
            identityContent
                .accessibilityElement(children: .combine)
        }
    }

    private var identityContent: some View {
        HStack(spacing: Spacing.md) {
            leading
                .frame(width: Self.leadingColumn, height: Self.leadingColumn)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Label {
                    Text(eyebrow)
                } icon: {
                    Image(systemName: symbol)
                }
                .labelStyle(EyebrowLabelStyle())
                .hooprType(.label)
                .foregroundStyle(tint)

                Text(title)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .hooprType(.caption)
                        .foregroundStyle(detailTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// A glyph tight against its word — `Label`'s default gap is sized for a
/// toolbar, and reads as two separate things at the eyebrow's 12pt.
private struct EyebrowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

/// The leading visual for a card that has no person or squad to show — a
/// match — drawn at the avatar's size so every card's text starts in one place.
struct InboxGlyph: View {
    let symbol: String
    var tint: Color = .hooprBrandAccent

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.hooprFill)
            Image(systemName: symbol)
                .font(.system(size: PlayerAvatar.Size.row * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.interRow) {
            InboxCard(
                eyebrow: "Upcoming match",
                symbol: "calendar",
                title: "3v3 vs Bull City Buckets",
                detail: "Tonight · 7:00 PM · East End Park",
                onOpen: {}
            ) {
                InboxGlyph(symbol: "basketball.fill")
            } actions: {
                EmptyView()
            }

            InboxCard(
                eyebrow: "Friend request",
                symbol: "person.badge.plus",
                title: "Jordan Ellis",
                onOpen: {}
            ) {
                PlayerAvatar(initial: "J", diameter: PlayerAvatar.Size.row)
            } actions: {
                Button("Accept") {}.buttonStyle(.hooprFilled(.compact))
                Button("Decline") {}.buttonStyle(.hooprFilled(.compact, role: .destructive))
            }

            InboxCard(
                eyebrow: "New friend",
                symbol: "person.2.fill",
                title: "Sam Ortiz",
                detail: "Accepted your friend request",
                onDismiss: {}
            ) {
                PlayerAvatar(initial: "S", diameter: PlayerAvatar.Size.row)
            } actions: {
                EmptyView()
            }
        }
        .padding(Spacing.pageMargin)
    }
    .background(Color.hooprBackground)
}
