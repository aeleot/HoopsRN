import SwiftUI

/// Find people, and see the people you've found — the Friends *pane* of the
/// profile screen.
///
/// This was the third tab of `MainTabView` until the shell needed that slot
/// back. Nothing about the screen changed in the move except who draws its
/// chrome: `ProfileView` owns the scroll view, the horizontal page padding and
/// the presentation state, and this file supplies the two pieces that go into
/// it — the toolbar that pins, and the list that scrolls.
///
/// **No collapsible sections.** This screen was never the same
/// two-dropdowns-over-a-`ScrollView` shape as `LocalRunsTab`, which fits that
/// tab because its two lists answer one question together ("am I busy, and what
/// else is on?"). A social screen isn't that: finding someone is an *action*
/// that needs a permanently visible control, and requests waiting on you
/// shouldn't be reachable only by expanding a dropdown. So the search field and
/// the inbox pin above a single list of people — as the profile's section
/// header, now that the profile owns the scroll — and the requests live in the
/// inbox behind a badge.
///
/// Everything a person can do to a relationship is available from
/// `PlayerProfileSheet`; the rows carry only the one action that's obvious in
/// context, so a list of friends stays a list rather than a stack of forms.
///
/// Both views here are stateless: they render what the view model holds and
/// report intent through closures. That's what lets the search field sit in a
/// pinned section header while the list sits in the section's body, with no
/// state stranded between them.
///
/// The field had the inbox button beside it until the inbox moved to the
/// profile's top bar — see `ProfileTopBar`, which explains why. What's left is
/// one control doing one thing, which is why this is a field rather than a
/// toolbar.
///
/// Same chrome as `HomeCourtPickerSheet`'s search field, so searching for a
/// person and searching for a court are visibly the same gesture.
struct FriendsSearchField: View {
    @ObservedObject var viewModel: FriendsViewModel

    /// Owned by the screen, so clearing the query can put the keyboard back and
    /// switching panes can take it away.
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HooprSearchField(
            text: $viewModel.searchQuery,
            placeholder: "Search by name or user ID",
            isFocused: isSearchFocused,
            // A user ID is case-sensitive and a name search is
            // case-insensitive, so autocapitalising either one only ever gets
            // in the way.
            capitalization: .never,
            // Clearing here drops the results too, not just the string.
            onClear: { viewModel.clearSearch() }
        )
    }
}

/// The list under the search field: friends, or search results while a query is
/// active. Carries no horizontal padding of its own — the screen around it sets
/// the page margin, and a list that padded itself would sit inset from the rows
/// above it.
struct FriendsPaneContent: View {
    @ObservedObject var viewModel: FriendsViewModel

    let onOpenPlayer: (String) -> Void
    /// Raised rather than performed: a removal is confirmed by the screen, so
    /// the dialog survives this row being re-created by a snapshot arriving
    /// mid-confirmation.
    let onRequestRemoval: (FriendsViewModel.Row) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    // Only when a listener is down. An action that failed — an
                    // accept that lost a race — has nothing here to retry; the
                    // user taps the button again.
                    onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.bottom, 12)
            }

            if viewModel.isSearchActive {
                searchResults
            } else {
                friendsList
            }
        }
    }

    // MARK: - Friends

    @ViewBuilder
    private var friendsList: some View {
        header(title: "Friends", countText: viewModel.friendsCountText)

        if viewModel.friends.isEmpty {
            message(viewModel.friendsEmptyText)
        } else {
            VStack(spacing: 10) {
                ForEach(viewModel.friends) { row in
                    FriendRow(
                        // Always the handle, never a home court. A subtitle
                        // that's a court on one row and a handle on the next
                        // means two different things in one column, and the
                        // handle is the one that identifies the person —
                        // `userName` isn't unique, so it's what distinguishes
                        // two friends with the same display name. The home
                        // court is on the profile, where it has a labelled row
                        // of its own.
                        row: row,
                        subtitle: row.handle,
                        onOpen: { onOpenPlayer(row.uid) }
                    ) {
                        friendMenu(for: row)
                    }
                }
            }
        }
    }

    /// The row's only inline action. Unfriending sits behind a menu *and* a
    /// confirmation because it's the one thing on this screen with nothing
    /// behind it — a declined request can be re-sent by the other person, but a
    /// removal is only undone by asking again.
    private func friendMenu(for row: FriendsViewModel.Row) -> some View {
        Menu {
            Button("View Profile") { onOpenPlayer(row.uid) }
            Button("Remove Friend", role: .destructive) { onRequestRemoval(row) }
        } label: {
            Group {
                if viewModel.pendingUid == row.uid {
                    ProgressView()
                        .tint(Color.hooprSecondaryText)
                } else {
                    Image(systemName: "ellipsis")
                        .hooprFont(17, weight: .semibold, maximumSize: 21)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .disabled(viewModel.pendingUid != nil)
        .opacity(viewModel.isBlocked(row.uid) ? 0.5 : 1)
        .accessibilityLabel("More options for \(row.nameForProse)")
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        switch viewModel.searchState {
        case .idle:
            EmptyView()

        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching…")
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

        case .empty:
            message(viewModel.searchEmptyText(for: viewModel.searchQuery))

        case .failed(let text):
            Text(text)
                .hooprFont(14)
                .foregroundStyle(Color.hooprRed)
                .padding(.top, 20)

        case .results:
            header(title: "Results", countText: "\(viewModel.searchRows.count)")

            VStack(spacing: 10) {
                ForEach(viewModel.searchRows) { row in
                    FriendRow(
                        row: row,
                        subtitle: row.handle,
                        onOpen: { onOpenPlayer(row.uid) }
                    ) {
                        resultControl(for: row)
                    }
                }
            }
        }
    }

    /// One control per result, never a row of them: a search result is a
    /// decision to *start* something. States with nothing quick to do — a
    /// request already sent, a friendship already made — read as a chip, and
    /// their full set of actions lives one tap away on the profile.
    @ViewBuilder
    private func resultControl(for row: FriendsViewModel.Row) -> some View {
        switch row.relationship {
        case .none, .incoming:
            // Resolved once and handed to both the button and its tap, so the
            // action that's rendered and the one that fires can't disagree —
            // the same rule `LocalRunsTab` follows for a game card.
            let action: FriendsViewModel.Action =
                row.relationship == .incoming ? .accept : .add

            FriendActionButton(
                action: action,
                isPending: viewModel.pendingUid == row.uid,
                isDisabled: viewModel.isBlocked(row.uid),
                playerName: row.nameForProse
            ) {
                Task { await viewModel.perform(action, on: row.uid) }
            }

        case .outgoing:
            FriendStateChip(title: "Requested", symbol: "clock")

        case .friends:
            FriendStateChip(title: "Friends", symbol: "checkmark")

        case .you:
            // Filtered out of results before they get here; rendering nothing
            // is the safe answer rather than an action that can't succeed.
            EmptyView()
        }
    }

    // MARK: - Shared pieces

    private func header(title: String, countText: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .hooprFont(18, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text(countText)
                .hooprFont(12, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.hooprFill))

            Spacer()
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .hooprFont(14)
            .foregroundStyle(Color.hooprSecondaryText)
            .multilineTextAlignment(.leading)
            .padding(.bottom, 20)
    }
}
