import SwiftUI
import UIKit

/// Who you are, set large at the top of the profile and scrolled past like any
/// other content.
///
/// **In the band, since UI revamp Phase 2b**: the
/// handle at `display`, and under it the one fact that identifies you *to other
/// people* — your home court, which is what a friend sees next to your name.
/// The uid stays, demoted to a caption, keeping its copy-on-tap.
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
    /// The home court's name, when one is set. Omitted rather than shown as
    /// "Not set": the Home Court row below is where it's set, and a hero line
    /// saying what's missing isn't a fact about you.
    var homeCourt: String? = nil

    /// Drives the uid's copy glyph, which reverts to itself after a beat.
    @State private var didCopy = false

    /// The pending revert, held so a second tap can cancel the first one's.
    /// Without this, tapping twice inside the revert window lets the earlier
    /// task clear the checkmark moments after the later tap set it — the one
    /// control whose whole job is confirming the copy, reading as a failure.
    @State private var revertTask: Task<Void, Never>?

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = PlayerAvatar.Size.profile

    var body: some View {
        // Centred, not leading: with the orange slab gone there's no bar for
        // the identity to sit inside any more, and a left-aligned avatar over a
        // left-aligned name reads as the first row of the list rather than as
        // the person the list belongs to.
        VStack(spacing: 14) {
            avatar

            VStack(spacing: 6) {
                Text(handle)
                    // Uncapped and wrapping: nothing pins this block's height,
                    // so it may grow as far as the reader's text size takes it.
                    // (It shrank to fit with `minimumScaleFactor(0.6)` before
                    // the revamp; the app no longer shrinks text anywhere.)
                    .hooprType(.display)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let homeCourt {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image.court
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprBrandAccent)
                            .accessibilityHidden(true)
                        Text(homeCourt)
                            .hooprType(.body)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Home court, \(homeCourt)")
                }

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
                    .stroke(Color.hooprBrandAccent, lineWidth: 2)
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
            // reading as a button. Each tap replaces the previous revert so the
            // window restarts rather than overlapping.
            revertTask?.cancel()
            revertTask = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
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
        .sensoryFeedback(.success, trigger: didCopy) { _, new in new }
        .accessibilityLabel("Copy user ID")
        .accessibilityValue(userId)
    }
}

/// The bar over the top of the profile: the inbox, always there, and a glass
/// background with the handle that arrives only once `ProfileIdentityBlock`
/// has scrolled behind it.
///
/// Applied as a `safeAreaInset` rather than a `ZStack` overlay, so the scroll
/// view treats it as safe area — that's what stops the pinned pane header
/// underneath it from sliding beneath the status bar.
///
/// **No back button** (2026-09-25). The profile is a tab now, not a screen
/// that replaced the tabs, so there is nothing behind it to go back to — the
/// tab bar is the way out, as it is from every other tab.
///
/// **The inbox is the shared `InboxButton`, in its shared slot.** It used to
/// be this bar's own tray, which sat 8pt higher and 14pt further right than
/// the button every other tab carries, and counted friend requests only. Now
/// the tray is the same control in the same place on all five tabs, and this
/// bar pads itself to `InboxButton.Slot` rather than the other way round.
struct ProfileTopBar: View {
    let handle: String
    let initial: String
    /// 0 while the identity block is still on screen, 1 once it's gone.
    let progress: Double

    @ObservedObject var friendService: FriendService
    @ObservedObject var squadService: SquadService

    let onOpenInbox: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 8) {
                PlayerAvatar(initial: initial, diameter: PlayerAvatar.Size.inline)

                Text(handle)
                    .hooprFont(17, weight: .semibold, maximumSize: 22)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Fades in with the bar. Hidden from VoiceOver throughout: the
            // handle is announced by the identity block, and a title that
            // appears on scroll isn't a second thing to read.
            .opacity(progress)
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            InboxButton(
                friendService: friendService,
                squadService: squadService,
                action: onOpenInbox
            )
        }
        .padding(.horizontal, Spacing.pageMargin)
        // The inbox button's slot — the same point on every tab.
        .padding(.top, InboxButton.Slot.top)
        .padding(.bottom, Spacing.xs)
        .frame(maxWidth: .infinity)
        // At rest the bar is the top row of the identity band, so it takes the
        // band's ground — not under the status bar, which stays the page
        // colour exactly as it does over every tab's band. Without this the
        // bar was a strip of page between the status bar and the band: the
        // "cuts off abruptly towards the top" the user flagged on squad detail
        // (2026-09-23). It fades out as the glass fades in.
        .background {
            Color.hooprHeroBand
                .opacity(1 - progress)
        }
        .background(alignment: .top) {
            // Glass once content scrolls under it. Extended past the top safe
            // area so the status bar sits on glass rather than on scrolling
            // rows.
            //
            // `contentShape` because a clear fill doesn't hit-test, and
            // content is scrolling directly underneath.
            Rectangle()
                .fill(.clear)
                .hooprGlass(interactive: false, in: .rect)
                .contentShape(Rectangle())
                .opacity(progress)
                .ignoresSafeArea(edges: .top)
        }
    }
}

#Preview {
    let authService = AuthService()
    VStack(spacing: 0) {
        ProfileTopBar(
            handle: "@Elliot",
            initial: "E",
            progress: 1,
            friendService: FriendService(authService: authService),
            squadService: SquadService(authService: authService),
            onOpenInbox: {}
        )

        ProfileIdentityBlock(
            handle: "@Elliot",
            initial: "EA",
            userId: "dQw4w9WgXcQaBcDeFgHiJkLmNoPq",
            homeCourt: "East End Park"
        )
        .padding(20)

        Spacer()
    }
    .background(Color.hooprBackground)
}
