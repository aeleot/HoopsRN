import SwiftUI

/// The Local Runs tab: the runs you're in, and the public ones near you.
///
/// Two collapsible sections over one scroll view rather than two lists — the
/// sections are read together ("am I busy, and what else is on?"), and stacking
/// them keeps a single scroll gesture in charge.
struct LocalRunsTab: View {
    @StateObject private var viewModel: LocalRunsViewModel

    /// Persisted rather than `@State`: this tab is unmounted whenever another
    /// tab is selected (see `UI_SHELL.md`), so plain view state would reopen
    /// both sections on every visit and quietly discard the choice.
    @AppStorage("localRuns.queuedExpanded") private var isQueuedExpanded = true
    @AppStorage("localRuns.publicExpanded") private var isPublicExpanded = true

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService
    ) {
        _viewModel = StateObject(wrappedValue: LocalRunsViewModel(
            gameService: gameService,
            courtService: courtService,
            userProfileService: userProfileService
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
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

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .hooprFont(13)

            Text(message)
                .hooprFont(13)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .hooprFont(12, weight: .semibold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(Color.hooprRed)
        .padding(12)
        .background(Color.hooprRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

#Preview {
    let authService = AuthService()
    return LocalRunsTab(
        gameService: GameService(authService: authService),
        courtService: CourtService(),
        userProfileService: UserProfileService(authService: authService)
    )
}
