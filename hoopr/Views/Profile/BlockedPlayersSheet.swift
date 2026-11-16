import SwiftUI

/// Everyone the signed-in user has blocked, each with the way back.
///
/// This is the only place a blocked player still appears — search and the
/// inbox hide them — so without it a block could never be undone.
struct BlockedPlayersSheet: View {
    @ObservedObject var viewModel: FriendsViewModel

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            onRetry: nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                    }

                    if viewModel.blockedPlayers.isEmpty {
                        Text(viewModel.blockedEmptyText)
                            .hooprType(.body)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Blocked players can't send you friend requests or squad invites. They aren't told.")
                            .hooprType(.caption)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        DividedRows {
                            ForEach(viewModel.blockedPlayers) { row in
                                playerRow(row)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hooprBackground)
            .navigationTitle("Blocked Players")
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
    }

    private func playerRow(_ row: FriendsViewModel.Row) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(initial: row.initial, diameter: PlayerAvatar.Size.roster)

            // An account that has since been deleted has no profile to
            // resolve; it still needs a row, or its block could never be
            // lifted.
            Text(row.isResolved ? row.nameForProse : "Player")
                .hooprType(.subhead)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.sm)

            FriendActionButton(
                action: .unblock,
                isPending: viewModel.pendingUid == row.uid,
                isDisabled: viewModel.isBlocked(row.uid),
                playerName: row.nameForProse
            ) {
                Task { await viewModel.perform(.unblock, on: row.uid) }
            }
        }
        .padding(.vertical, 10)
    }
}
