import SwiftUI

/// The Local Runs tab: the runs you're in, and the public ones near you.
///
/// Two collapsible sections over one scroll view rather than two lists — the
/// sections are read together ("am I busy, and what else is on?"), and stacking
/// them keeps a single scroll gesture in charge.
struct LocalRunsTab: View {
    @StateObject private var viewModel: LocalRunsViewModel

    /// Persisted rather than `@State`. This was written when a tab switch
    /// unmounted the tab entirely and plain view state would reopen both
    /// sections on every visit. Under a native `TabView` the tab stays mounted,
    /// so `@State` would now survive a switch — but this still earns its keep
    /// by carrying the choice across launches, which `@State` never did.
    @AppStorage("localRuns.queuedExpanded") private var isQueuedExpanded = true
    @AppStorage("localRuns.publicExpanded") private var isPublicExpanded = true

    /// Observed because `ProfileButton` reads it for its badge dot.
    @ObservedObject private var friendService: FriendService

    private let onOpenProfile: () -> Void

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService,
        friendService: FriendService,
        onOpenProfile: @escaping () -> Void
    ) {
        self.friendService = friendService
        self.onOpenProfile = onOpenProfile
        _viewModel = StateObject(wrappedValue: LocalRunsViewModel(
            gameService: gameService,
            courtService: courtService,
            userProfileService: userProfileService
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        // Only when a listener is down. An action that failed —
                        // a join that lost a race — has nothing here to retry;
                        // the user taps the card's button again.
                        onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                        onDismiss: { viewModel.dismissError() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                section(
                    title: "Queued Games",
                    countText: viewModel.queuedCountText,
                    isExpanded: $isQueuedExpanded,
                    listings: viewModel.queued,
                    emptyText: viewModel.queuedEmptyText
                )

                Rectangle()
                    .fill(Color.hooprBorder)
                    .frame(height: 1)

                section(
                    title: "Public Games",
                    countText: viewModel.nearbyCountText,
                    isExpanded: $isPublicExpanded,
                    listings: viewModel.nearby,
                    emptyText: viewModel.nearbyEmptyText
                )
            }
            .padding(.bottom, 32)
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    /// This tab used to borrow the shell's floating header for both its title
    /// and its profile button. With the tab bar at the bottom that header is
    /// gone, so the tab names itself.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Runs")
                .hooprFont(28, weight: .bold, maximumSize: 40)
                .foregroundStyle(Color.hooprPrimaryText)

            Spacer(minLength: 8)

            ProfileButton(friendService: friendService, action: onOpenProfile)
                .offset(x: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(
        title: String,
        countText: String,
        isExpanded: Binding<Bool>,
        listings: [LocalRunsViewModel.Listing],
        emptyText: String
    ) -> some View {
        sectionHeader(title: title, countText: countText, isExpanded: isExpanded)

        if isExpanded.wrappedValue {
            if listings.isEmpty {
                Text(emptyText)
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(listings) { listing in
                        // Resolved once, so the button that's rendered and the
                        // one that fires can't disagree — a confirmation
                        // dialog reading "Cancel run" must not perform a join.
                        let action = viewModel.action(for: listing)

                        GameCard(
                            listing: listing,
                            action: action,
                            isHost: viewModel.isHost(listing),
                            isWaitlisted: viewModel.isWaitlisted(listing),
                            isPending: viewModel.pendingGameId == listing.id,
                            // One roster write at a time, so a second tap can't
                            // race the transaction already in flight.
                            isDisabled: viewModel.pendingGameId != nil
                                && viewModel.pendingGameId != listing.id,
                            onAction: {
                                Task { await viewModel.perform(action, on: listing) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func sectionHeader(
        title: String,
        countText: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
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

                Image(systemName: "chevron.right")
                    .hooprFont(14, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded.wrappedValue ? "collapse" : "expand")")
    }
}

#Preview {
    let authService = AuthService()
    LocalRunsTab(
        gameService: GameService(authService: authService),
        courtService: CourtService(),
        userProfileService: UserProfileService(authService: authService),
        friendService: FriendService(authService: authService),
        onOpenProfile: {}
    )
}
