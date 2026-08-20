import SwiftUI

/// The Friends tab: find people, and see the people you've found.
///
/// **No collapsible sections.** This screen used to be the same
/// two-dropdowns-over-a-`ScrollView` shape as `LocalRunsTab`, which fits that
/// tab because its two lists answer one question together ("am I busy, and
/// what else is on?"). A social screen isn't that: finding someone is an
/// *action* that needs a permanently visible control, and requests waiting on
/// you shouldn't be reachable only by expanding a dropdown. So the search field
/// and the inbox are pinned above a single list of people, and the requests
/// moved into the inbox behind a badge.
///
/// Everything a person can do to a relationship is available from
/// `PlayerProfileSheet`; the rows carry only the one action that's obvious in
/// context, so a list of friends stays a list rather than a stack of forms.
struct FriendsTab: View {
    @StateObject private var viewModel: FriendsViewModel

    @FocusState private var isSearchFocused: Bool
    @State private var isInboxPresented = false

    /// This screen's own profile route — see `PlayerRoute`.
    @State private var presentedPlayer: PlayerRoute?

    /// Which friend a remove confirmation is about. Held here rather than on the
    /// row so the dialog survives the row being re-created by a snapshot
    /// arriving mid-confirmation.
    @State private var pendingRemoval: FriendsViewModel.Row?

    init(
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService
    ) {
        _viewModel = StateObject(wrappedValue: FriendsViewModel(
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            // Only when a listener is down. An action that
                            // failed — an accept that lost a race — has nothing
                            // here to retry; the user taps the button again.
                            onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    if viewModel.isSearchActive {
                        searchResults
                    } else {
                        friendsList
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isInboxPresented) {
            InboxSheet(viewModel: viewModel) {
                isInboxPresented = false
            }
        }
        .sheet(item: $presentedPlayer) { route in
            PlayerProfileSheet(uid: route.uid, viewModel: viewModel) {
                presentedPlayer = nil
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.nameForProse ?? "this player")?",
            isPresented: .init(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let uid = pendingRemoval?.uid {
                    Task { await viewModel.perform(.remove, on: uid) }
                }
                pendingRemoval = nil
            }
            Button("Keep", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You'll both drop off each other's friends list. You can add them again later.")
        }
    }

    // MARK: - Toolbar

    /// Pinned above the scroll view: the one control that finds people, and the
    /// one that shows what's waiting. Neither may scroll away.
    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField
            inboxButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// Same chrome as `HomeCourtPickerSheet`'s search field, so searching for a
    /// person and searching for a court are visibly the same gesture.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .hooprFont(15, weight: .medium, maximumSize: 20)
                .foregroundStyle(Color.hooprSecondaryText)

            TextField("Search by name or user ID", text: $viewModel.searchQuery)
                .hooprFont(16, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                #if os(iOS) || os(visionOS)
                // A user ID is case-sensitive and a name search is
                // case-insensitive, so autocapitalising either one only ever
                // gets in the way.
                .textInputAutocapitalization(.never)
                #endif

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .hooprFont(15, maximumSize: 20)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchFocused ? Color.hooprOrange : Color.hooprBorder, lineWidth: 1)
        )
    }

    /// A tray, not a bell: this is where social notifications collect, and the
    /// app has no push infrastructure to make a bell honest.
    private var inboxButton: some View {
        Button {
            isSearchFocused = false
            isInboxPresented = true
        } label: {
            Image(systemName: "tray.fill")
                .hooprFont(18, weight: .medium, maximumSize: 22)
                .foregroundStyle(Color.hooprPrimaryText)
                .frame(width: 48, height: 48)
                .background(Color.hooprFill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.hooprBorder, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if viewModel.hasUnanswered {
                        Text(viewModel.badgeText)
                            .hooprFont(11, weight: .bold, maximumSize: 13)
                            .foregroundStyle(Color.hooprOnBrand)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color.hooprOrange))
                            // A ring in the page colour, so the badge reads as
                            // sitting on top of the button rather than as part
                            // of its border.
                            .overlay(Capsule().stroke(Color.hooprBackground, lineWidth: 2))
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inbox")
        .accessibilityValue(
            viewModel.hasUnanswered
                ? "\(viewModel.unansweredCount) requests waiting"
                : "Nothing waiting"
        )
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
                        // court is on the profile, where it has a labelled
                        // card of its own.
                        row: row,
                        subtitle: row.handle,
                        onOpen: { presentedPlayer = PlayerRoute(uid: row.uid) }
                    ) {
                        friendMenu(for: row)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// The row's only inline action. Unfriending sits behind a menu *and* a
    /// confirmation because it's the one thing on this screen with nothing
    /// behind it — a declined request can be re-sent by the other person, but a
    /// removal is only undone by asking again.
    private func friendMenu(for row: FriendsViewModel.Row) -> some View {
        Menu {
            Button("View Profile") {
                presentedPlayer = PlayerRoute(uid: row.uid)
            }
            Button("Remove Friend", role: .destructive) {
                pendingRemoval = row
            }
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
                .padding(.horizontal, 16)
                .padding(.top, 20)

        case .results:
            header(title: "Results", countText: "\(viewModel.searchRows.count)")

            VStack(spacing: 10) {
                ForEach(viewModel.searchRows) { row in
                    FriendRow(
                        row: row,
                        subtitle: row.handle,
                        onOpen: { presentedPlayer = PlayerRoute(uid: row.uid) }
                    ) {
                        resultControl(for: row)
                    }
                }
            }
            .padding(.horizontal, 16)
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .hooprFont(14)
            .foregroundStyle(Color.hooprSecondaryText)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
    }
}

#Preview {
    let authService = AuthService()
    return FriendsTab(
        friendService: FriendService(authService: authService),
        userProfileService: UserProfileService(authService: authService),
        courtService: CourtService()
    )
}
