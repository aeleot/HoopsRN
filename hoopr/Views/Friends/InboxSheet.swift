import SwiftUI

/// Everything social that's waiting on you, and everything you're waiting on.
///
/// Opened from the Friends tab's top-right corner and badged with the number of
/// unanswered requests. Friend requests are the only thing that lands here
/// today; a second kind of notification costs a second section, which is why
/// there's **no notification-kind abstraction** — an `InboxItem` enum with one
/// case would be invented structure, not shared structure.
///
/// Two plain titled sections rather than collapsibles. There are at most two of
/// them, both short, and the whole point of moving requests off the main tab was
/// to stop making people open a dropdown to find out whether anything was
/// waiting.
struct InboxSheet: View {
    @ObservedObject var viewModel: FriendsViewModel

    let onDismiss: () -> Void

    /// This sheet's own profile route — see `PlayerRoute`.
    @State private var presentedPlayer: PlayerRoute?

    private var isEmpty: Bool {
        viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty
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
                        .foregroundStyle(Color.hooprBrandText)
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
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        } else {
            VStack(spacing: 10) {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .hooprFont(18, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("\(count)")
                .hooprFont(12, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.hooprFill))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
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
                .hooprFont(15)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
