import SwiftUI

/// One season match in the inbox — a row in `DividedRows`, like
/// `SquadInviteRow` beside it. The whole row is the button: it opens game day
/// for a match to come, or the result screen for one waiting on your report.
///
/// Lives with the other inbox rows rather than in `Views/Seasons/` for the
/// reason `SquadInviteRow` does: the inbox is its only home.
struct MatchInboxRow: View {
    /// The leading glyph's column — `SquadCrest.Size.card`, so the matches'
    /// hairlines start where the squad invites' do.
    static let glyphColumn: CGFloat = SquadCrest.Size.card
    static let textInset: CGFloat = glyphColumn + 12

    let row: InboxMatchesViewModel.Row
    let detail: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprBrandAccent)
                    .frame(width: Self.glyphColumn)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.game.format.displayName) vs \(row.opponentName)")
                        .hooprType(.subhead)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .hooprType(.caption)
                        .foregroundStyle(row.kind == .upcoming ? Color.hooprSecondaryText : Color.hooprBrandAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.kind == .upcoming ? "Opens game day" : "Opens the result")
    }

    private var symbol: String {
        switch row.kind {
        case .upcoming: "calendar"
        case .report: "square.and.pencil"
        case .disputed: "exclamationmark.triangle.fill"
        }
    }
}
