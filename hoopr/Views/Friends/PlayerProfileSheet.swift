import SwiftUI

/// A uid, wrapped so `.sheet(item:)` can present a profile from it.
///
/// Each screen that opens a profile keeps its own `@State` route rather than
/// sharing one published selection on the view model — the Friends tab and the
/// inbox are both on screen at once when the inbox is open, and two presenters
/// bound to one optional fight over it.
struct PlayerRoute: Identifiable, Hashable {
    let uid: String
    var id: String { uid }
}

/// Another player's profile — what you look at before deciding to add someone,
/// and where every action on the relationship lives.
///
/// **Shows three things, deliberately: name, home court, joined.** That is a
/// *display* decision, not an access control: `users` documents are readable by
/// any signed-in account and Firestore has no field-level read ACLs, so a
/// document is readable whole or not at all (see
/// `context/database/DATABASE_SCHEMA.md`). What this screen chooses not to
/// render — `favoriteCourtIds`, `preferredRadius` — is a location pattern and a
/// personal setting that inform nothing about whether to add someone, and the
/// schema doc already flags both as worth re-examining. Making them genuinely
/// private is the owner-only-subcollection migration named there, not this file.
///
/// Friend counts and mutual friends aren't merely omitted, they're impossible:
/// `friendships` is readable only by its two participants, so no query this app
/// can make would produce them.
///
/// Holds a **uid**, never a snapshot of a profile: it reads back through
/// `FriendsViewModel` on every render, so a name landing or a request being
/// accepted on the other device updates the open sheet.
struct PlayerProfileSheet: View {
    let uid: String

    @ObservedObject var viewModel: FriendsViewModel

    let onDismiss: () -> Void

    @State private var isConfirmingRemove = false

    /// One grid unit, scaled with the reader's text size — the same
    /// `@ScaledMetric` floor `ProfileView` gives its own cards.
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 80

    private var row: FriendsViewModel.Row { viewModel.row(for: uid) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                identityHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        cards
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
            }
            .background(Color.hooprBackground)
            // Pinned as a safe-area inset rather than the last item in the
            // stack, matching `ProfileView`'s Sign Out bar: a growing card list
            // can never push the action off the bottom edge.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .navigationTitle("Profile")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // On-brand white, not orange: the identity band is the
                    // first thing in the stack, so the translucent bar sits
                    // directly over the gradient and an orange label there is
                    // orange on orange.
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprOnBrand)
                }
            }
        }
        // Heals a row whose name never resolved — a batch lookup that failed, or
        // a profile fetched after this sheet was already opening.
        .task { await viewModel.loadProfileIfNeeded(for: uid) }
        .confirmationDialog(
            "Remove \(row.nameForProse)?",
            isPresented: $isConfirmingRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.perform(.remove, on: uid) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("You'll both drop off each other's friends list. You can add them again later.")
        }
    }

    // MARK: - Header

    /// The same orange identity band `ProfileView` opens on, so a profile reads
    /// as a profile wherever it appears — **without the uid row**. Copying out
    /// your own ID is the sharing flow; republishing someone else's identifier
    /// serves nothing.
    private var identityHeader: some View {
        HStack(spacing: 14) {
            PlayerAvatar(initial: row.initial, diameter: 56, onBrand: true)
                .overlay(
                    Circle()
                        .stroke(Color.hooprOnBrand.opacity(0.35), lineWidth: 2)
                        .frame(width: 62, height: 62)
                )

            if row.isResolved {
                Text(row.handle.isEmpty ? row.nameForProse : row.handle)
                    .hooprFont(22, weight: .bold, maximumSize: 28)
                    .foregroundStyle(Color.hooprOnBrand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.hooprOnBrand.opacity(0.3))
                    .frame(width: 150, height: 18)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.hooprBrand, Color.hooprBrandDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Cards

    /// `ProfileCard` with `onEdit: nil` — the component's existing way of saying
    /// read-only, which is exactly what someone else's profile is. Reusing it
    /// means these cards can't drift from the ones on your own profile screen.
    @ViewBuilder
    private var cards: some View {
        ProfileCard(
            symbol: "basketball.fill",
            label: "Home Court",
            value: row.profile.flatMap { viewModel.homeCourtName(for: $0) },
            placeholder: row.isResolved ? "Not set" : "—",
            detail: row.profile.flatMap { viewModel.homeCourtCity(for: $0) },
            prominence: .feature
        )
        .frame(minHeight: tileHeight * 1.4)

        ProfileCard(
            symbol: "calendar",
            label: "Joined",
            value: joinedText,
            placeholder: "—"
        )
        .frame(minHeight: tileHeight)
    }

    /// Month and year only. A precise join date is more than a stranger needs,
    /// and the profile screen's own `Joined` card already reads this way.
    private var joinedText: String? {
        guard let createdAt = row.profile?.createdAt else { return nil }
        return createdAt.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        let actions = viewModel.actions(for: row.relationship)

        // Nothing to act on means no bar at all — an empty rule and a strip of
        // padding would read as something that failed to load. Only reachable
        // for your own profile, which search already filters out.
        if !actions.isEmpty {
            bar(actions)
        }
    }

    private func bar(_ actions: [FriendsViewModel.Action]) -> some View {
        VStack(spacing: 0) {
            // The cards scroll under this bar, so it needs an edge of its own —
            // without the rule a card is simply cut off mid-height.
            Rectangle()
                .fill(Color.hooprBorder)
                .frame(height: 1)

            VStack(spacing: 10) {
                if let status = statusText {
                    Label(status.text, systemImage: status.symbol)
                        .hooprFont(14, weight: .medium)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                HStack(spacing: 10) {
                    ForEach(actions, id: \.self) { action in
                        FriendActionButton(
                            action: action,
                            size: .wide,
                            isPending: viewModel.pendingUid == uid,
                            isDisabled: viewModel.isBlocked(uid),
                            playerName: row.nameForProse
                        ) {
                            // Unfriending is the one action with nothing behind
                            // it — a declined request can be re-sent by the
                            // other person, but a removal is only undone by
                            // asking again.
                            if action == .remove {
                                isConfirmingRemove = true
                            } else {
                                Task { await viewModel.perform(action, on: uid) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .background(Color.hooprBackground)
    }

    /// The line above the buttons, naming the state the buttons act on. `.none`
    /// has none — "Add Friend" already says everything there is to say.
    private var statusText: (text: String, symbol: String)? {
        switch row.relationship {
        case .friends:  ("You're friends", "checkmark.circle.fill")
        case .incoming: ("Sent you a request", "envelope.fill")
        case .outgoing: ("Request sent", "clock.fill")
        case .none, .you: nil
        }
    }
}
