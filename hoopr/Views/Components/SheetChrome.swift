import SwiftUI

/// A sheet's answer, in one block: the glyph, the one-line heading, and the
/// sentence under it — the create sheet's "Your run is set", and every state
/// the invite sheet lands in, so a run reads the same whether you are making
/// one or being asked to one. One view rather than a private copy per sheet,
/// so a change to the glyph's size or the heading's role lands on both.
struct SheetHeading: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .hooprFont(40, maximumSize: 56)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)

            Text(title)
                .hooprType(.title)
                .foregroundStyle(Color.hooprPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A validation hint, a failed write, or a refused join: red, marked, and one
/// line where it fits — under the control it answers.
struct ProblemLine: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .hooprType(.caption)
                .accessibilityHidden(true)
            Text(message)
                .hooprType(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.hooprRed)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        SheetHeading(
            symbol: "checkmark.circle.fill",
            title: "Your run is set",
            message: "Send your players the link. It opens this run in the app so they can join."
        )
        ProblemLine(message: "Couldn't save this run. Check your connection.")
    }
    .padding(Spacing.pageMargin)
    .background(Color.hooprGroupedBackground)
}
