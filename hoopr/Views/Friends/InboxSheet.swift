import SwiftUI

/// Everything social that's waiting on you, and everything you're waiting on.
///
/// Opened from the profile's top-right corner and badged with the number of
/// unanswered requests — see `ProfileButton`. Friend requests were the only
/// thing that landed here at first; squad invites are the second kind, and
/// true to the plan, that cost exactly one more section rather than a
/// notification-kind abstraction — an `InboxItem` enum for two cases would
/// still be invented structure, not shared structure. Squad invites used to
/// render inline on Squad home; there's nowhere left for a second kind of
/// notification to hide once there's a dedicated inbox for the first.
///
/// Plain titled sections rather than collapsibles. There are at most three of
/// them, all short, and the whole point of moving requests off the main tab was
/// to stop making people open a dropdown to find out whether anything was
/// waiting.
struct InboxSheet: View {
    @ObservedObject var viewModel: FriendsViewModel
    @ObservedObject var squadViewModel: SquadViewModel

    let onDismiss: () -> Void

    /// This sheet's own profile route — see `PlayerRoute`.
    @State private var presentedPlayer: PlayerRoute?

    private var isEmpty: Bool {
        viewModel.incomingRequests.isEmpty
            && viewModel.outgoingRequests.isEmpty
            && squadViewModel.incomingInvites.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Requests first and always shown, even when empty
                            // alongside sent ones: it's the section the badge
                            // counts, so its absence would be ambiguous.
                            section(
                                title: "Requests",
                                rows: viewModel.incomingRequests,
                                emptyText: viewModel.requestsEmptyText,
                                subtitle: "Wants to add you"
                            )

                            // Unlike the two friend sections, this one is
                            // omitted rather than shown empty — a squad invite
                            // is rarer than a friend request, and a "nothing
                            // here" placeholder for it on every visit would
                            // outweigh the one time it has something to say.
                            if !squadViewModel.incomingInvites.isEmpty {
                                squadInvitesSection
                            }

                            section(
                                title: "Sent",
                                rows: viewModel.outgoingRequests,
                                emptyText: viewModel.sentEmptyText,
                                subtitle: "Request sent"
                            )
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.hooprBackground)
            .navigationTitle("Inbox")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprBrandAccent)
                }
            }
        }
        .sheet(item: $presentedPlayer) { route in
            PlayerProfileSheet(uid: route.uid, viewModel: viewModel) {
                presentedPlayer = nil
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(
        title: String,
        rows: [FriendsViewModel.Row],
        emptyText: String,
        /// One line for the whole section — every row in it is in the same
        /// state, which is what the section *is*.
        subtitle: String
    ) -> some View {
        sectionHeader(title: title, count: rows.count)

        if rows.isEmpty {
            Text(emptyText)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.bottom, Spacing.lg)
        } else {
            DividedRows(leadingInset: FriendRow<EmptyView>.textInset) {
                ForEach(rows) { row in
                    FriendRow(
                        row: row,
                        subtitle: subtitle,
                        onOpen: { presentedPlayer = PlayerRoute(uid: row.uid) }
                    ) {
                        actions(for: row)
                    }
                }
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var squadInvitesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Squad invites", count: squadViewModel.incomingInvites.count)

            DividedRows(leadingInset: SquadCrest.Size.card + 12) {
                ForEach(squadViewModel.incomingInvites) { row in
                    SquadInviteRow(
                        row: row,
                        isBlocked: squadViewModel.isBlocked(row.id),
                        joinBlockedReason: squadViewModel.joinBlockedReason(for: row.invite),
                        onAccept: { Task { await squadViewModel.acceptInvite(row.invite) } },
                        onDecline: { Task { await squadViewModel.declineInvite(row.invite) } }
                    )
                }
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.lg)
        }
    }

    /// A `label` with its count at the trailing edge, as the Friends pane and
    /// Seasons' roster head their lists. The count used to sit in a filled
    /// capsule beside an 18pt bold title.
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            Spacer()

            Text("\(count)")
                .hooprType(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.hooprSecondaryText)
                .hooprNumericTransition(count)
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Every action the relationship offers, inline — this is the screen whose
    /// whole job is answering, so nothing here hides behind a profile.
    private func actions(for row: FriendsViewModel.Row) -> some View {
        HStack(spacing: 8) {
            ForEach(viewModel.actions(for: row.relationship), id: \.self) { action in
                FriendActionButton(
                    action: action,
                    isPending: viewModel.pendingUid == row.uid,
                    isDisabled: viewModel.isBlocked(row.uid),
                    playerName: row.nameForProse
                ) {
                    Task { await viewModel.perform(action, on: row.uid) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .hooprFont(38, maximumSize: 48)
                .foregroundStyle(Color.hooprSecondaryText)

            Text(viewModel.inboxEmptyText)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
