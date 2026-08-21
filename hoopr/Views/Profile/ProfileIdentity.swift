import SwiftUI
import UIKit

/// Who you are, set large at the top of the profile and scrolled past like any
/// other content.
///
/// This replaces the pinned orange slab the screen used to open with. A fixed
/// fraction of the screen painted in the brand colour spent the most valuable
/// real estate on the page restating something the user already knows, and it
/// pinned the app's loudest colour permanently under the status bar. Here the
/// identity is content: it reads first, then it goes away, and what's left is
/// the compact bar in `ProfileTopBar`. Orange survives as the avatar's ring and
/// the row icons — an accent, not a ground.
struct ProfileIdentityBlock: View {
    /// Already in `@handle` form; see `ProfileView.handle` for why the display
    /// name is rendered rather than stored that way.
    let handle: String
    /// Up to two letters, or empty for the fallback glyph.
    let initial: String
    /// `nil` while the session resolves.
    let userId: String?

    /// Drives the uid's copy glyph, which reverts to itself after a beat.
    @State private var didCopy = false

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 72

    var body: some View {
        // Centred, not leading: with the orange slab gone there's no bar for
        // the identity to sit inside any more, and a left-aligned avatar over a
        // left-aligned name reads as the first row of the list rather than as
        // the person the list belongs to.
        VStack(spacing: 14) {
            avatar

            VStack(spacing: 4) {
                Text(handle)
                    // Uncapped, unlike the old header's type: nothing pins this
                    // block's height any more, so it may grow as far as the
                    // reader's text size takes it.
                    .hooprFont(30, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)

                if let userId {
                    copyableUserId(userId)
                } else {
                    // Holds the line while the session resolves, so the handle
                    // above doesn't shift when the uid lands.
                    Text(" ").hooprFont(12)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        PlayerAvatar(initial: initial, diameter: diameter)
            .overlay(
                Circle()
                    .stroke(Color.hooprOrange, lineWidth: 2)
                    .frame(width: diameter + 8, height: diameter + 8)
            )
    }

    /// The uid, with a tap that puts it on the pasteboard — quoting it in a bug
    /// report is the only reason it's on screen, and a 28-character string is
    /// not something anyone should retype.
    ///
    /// The glyph swaps to a checkmark on success rather than raising a toast:
    /// the confirmation belongs where the tap was.
    private func copyableUserId(_ userId: String) -> some View {
        Button {
            UIPasteboard.general.string = userId
            didCopy = true
            // Reverts on its own; a copy affordance that stays "copied" stops
            // reading as a button.
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                didCopy = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(userId)
                    .hooprFont(12)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .hooprFont(11, weight: .semibold, maximumSize: 15)
                    // The symbol animates between the two states rather than
                    // being swapped out from under the reader.
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(Color.hooprSecondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy user ID")
        .accessibilityValue(userId)
    }
}

/// The bar over the top of the profile: a back chevron and the inbox, both
/// always there, and a glass background with the handle that arrives only once
/// `ProfileIdentityBlock` has scrolled behind it.
///
/// Applied as a `safeAreaInset` rather than a `ZStack` overlay, so the scroll
/// view treats it as safe area — that's what stops the pinned pane header
/// underneath it from sliding beneath the status bar.
///
/// **The inbox lives here, not in the Friends pane.** It was a second button
/// beside that pane's search field, which meant the one place social
/// notifications collect was only visible on the pane you had to already be on
/// to see it. Screen chrome is the honest home for it: it's reachable from
/// either pane, it doesn't scroll, and the badge on it is the profile's
/// notification indicator rather than one pane's.
struct ProfileTopBar: View {
    let handle: String
    let initial: String
    /// 0 while the identity block is still on screen, 1 once it's gone.
    let progress: Double

    /// Unanswered incoming requests. Zero hides the badge entirely.
    let unansweredCount: Int
    /// The count as the badge renders it, capped by the caller.
    let badgeText: String

    let onBack: () -> Void
    let onOpenInbox: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .hooprFont(18, weight: .semibold, maximumSize: 23)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to home")

            HStack(spacing: 8) {
                PlayerAvatar(initial: initial, diameter: 28)

                Text(handle)
                    .hooprFont(17, weight: .semibold, maximumSize: 22)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Fades in with the bar. Hidden from VoiceOver throughout: the
            // handle is announced by the identity block, and a title that
            // appears on scroll isn't a second thing to read.
            .opacity(progress)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            inboxButton
        }
        .padding(.trailing, 6)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // Same glass the shell header floats on, so arriving at the profile
            // from the map doesn't change what a bar is made of. Extended past
            // the top safe area so the status bar sits on glass rather than on
            // scrolling rows.
            //
            // `contentShape` for the reason `MainTabView` documents at length:
            // a clear fill doesn't hit-test, and content is scrolling directly
            // underneath.
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .contentShape(Rectangle())
                .opacity(progress)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// A tray, not a bell: this is where social notifications collect, and the
    /// app has no push infrastructure to make a bell honest.
    ///
    /// The badge is `hooprRed` — the one thing on the screen asking to be dealt
    /// with, in the colour the app reserves for exactly that. Orange is the
    /// brand and is everywhere here; a badge in it says "waiting" no louder
    /// than the row icons beside it do.
    private var inboxButton: some View {
        Button(action: onOpenInbox) {
            Image(systemName: "tray.fill")
                .hooprFont(17, weight: .medium, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if unansweredCount > 0 {
                        Text(badgeText)
                            .hooprFont(11, weight: .bold, maximumSize: 13)
                            .foregroundStyle(Color.hooprOnBrand)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color.hooprRed))
                            // A ring in the page colour, so the badge reads as
                            // sitting on top of the tray rather than as part of
                            // its shape.
                            .overlay(Capsule().stroke(Color.hooprBackground, lineWidth: 2))
                            .offset(x: -2, y: 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inbox")
        .accessibilityValue(
            unansweredCount > 0
                ? "\(unansweredCount) requests waiting"
                : "Nothing waiting"
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        ProfileTopBar(
            handle: "@Elliot",
            initial: "E",
            progress: 1,
            unansweredCount: 2,
            badgeText: "2",
            onBack: {},
            onOpenInbox: {}
        )

        ProfileIdentityBlock(
            handle: "@Elliot",
            initial: "EA",
            userId: "dQw4w9WgXcQaBcDeFgHiJkLmNoPq"
        )
        .padding(20)

        Spacer()
    }
    .background(Color.hooprBackground)
}
