import SwiftUI

/// A run's invite link, with a tap that puts it on the pasteboard.
///
/// Shared by the create sheet's confirmation step and the host's card on the
/// Runs board so the two can't diverge — the link is shown, not just copied,
/// because a host who has already sent it needs to recognize it.
///
/// **It now says what the link actually does.** A host can copy
/// `hoopsrn://game/{id}` and that is the whole of it: the scheme is not
/// registered, nothing implements `.onOpenURL`, and the `games` read rule
/// refuses a non-member — so a recipient who taps it gets nothing, and **an
/// invite-only run still holds only its host** (`gaps/GAMES.md`). Both
/// surfaces presented it as a working invite. Drawing a feature as working
/// that a gap file says isn't is an automatic fail under the revamp's purpose rule, so
/// the note below is a correctness fix, not copy polish, and it lives on the
/// component so neither surface can drift back.
///
/// It is not a bare disclaimer: it names the thing that *does* work, which is
/// telling people the court and the time.
///
/// The copy confirmation swaps the glyph in place and reverts, matching the
/// uid on the profile header rather than raising a toast neither surface has
/// room for.
struct InviteLinkCard: View {
    let link: String
    /// A line above the link. `nil` renders the compact form used on a card,
    /// where the surrounding row already says what this is.
    var caption: String?

    /// What the link can't do yet. On by default on every surface.
    var showsUnopenableNote: Bool = true

    @State private var didCopy = false

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 6) {
                if let caption {
                    Text(caption)
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .hooprFont(12, weight: .semibold, maximumSize: 16)
                        .foregroundStyle(Color.hooprBrandAccent)

                    Text(link)
                        .hooprFont(13, maximumSize: 16)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .hooprFont(12, weight: .semibold, maximumSize: 16)
                            .contentTransition(.symbolEffect(.replace))
                        Text(didCopy ? "Copied" : "Copy")
                            .hooprFont(12, weight: .semibold, maximumSize: 16)
                    }
                    .foregroundStyle(Color.hooprBrandAccent)
                }

                if showsUnopenableNote {
                    Text("Opening this link doesn't work yet — send the court and time too.")
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hooprFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.hooprBorder, lineWidth: 1)
            )
            // The link itself is the target, not just the glyph — the row is
            // one gesture wide.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A copy has nothing on screen to show for itself but this glyph, so
        // it's felt too — only on the copy, not when the glyph reverts.
        .sensoryFeedback(.success, trigger: didCopy) { _, new in new }
        .accessibilityLabel("Copy invite link. Opening it does not work yet.")
        .accessibilityValue(didCopy ? "Copied" : link)
    }

    private func copy() {
        UIPasteboard.general.string = link
        withAnimation(.hooprSnap) {
            didCopy = true
        }
        // Reverts on its own; a copy affordance that stays "copied" stops
        // reading as a button.
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.hooprSnap) {
                didCopy = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        InviteLinkCard(
            link: InviteLink.text(forGameId: "5FQxT2mKpLwd0aZbYc19"),
            caption: "Send this to the players you want in."
        )
        InviteLinkCard(link: InviteLink.text(forGameId: "5FQxT2mKpLwd0aZbYc19"))
    }
    .padding()
    .background(Color.hooprBackground)
}
