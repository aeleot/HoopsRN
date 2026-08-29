import SwiftUI

/// The Seasons tab — plan §5, screens 1 and 2.
///
/// Two states over one scroll view. With no squad it's a hero empty state that
/// explains what a season *is* before asking for anything; with a squad it's
/// squad home — crest, record, roster, and the one card that matters right now.
///
/// **The matchmaking card says out loud that matchmaking isn't built yet.** A
/// disabled button with no explanation would read as a bug on the user's
/// account rather than as a feature that hasn't shipped, and the honest version
/// costs one sentence.
struct SeasonsTab: View {
    @StateObject private var viewModel: SquadViewModel

    /// Observed because `ProfileButton` reads it for its badge dot.
    @ObservedObject private var friendService: FriendService

    private let onOpenProfile: () -> Void

    /// Wrapped for `sheet(item:)` rather than presented with `isPresented` —
    /// the house convention, and the one that survives a rapid re-tap without
    /// going inert.
    private struct CreateRoute: Identifiable {
        let id = "create-squad"
    }

    @State private var creating: CreateRoute?
    @State private var path: [String] = []

    init(
        squadService: SquadService,
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        onOpenProfile: @escaping () -> Void
    ) {
        self.friendService = friendService
        self.onOpenProfile = onOpenProfile
        _viewModel = StateObject(wrappedValue: SquadViewModel(
            squadService: squadService,
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            // Only when a listener is down. An action that
                            // failed is retried by repeating the action.
                            onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                    }

                    if !viewModel.incomingInvites.isEmpty {
                        invitesSection
                    }

                    if !viewModel.hasLoaded {
                        loading
                    } else if let squad = viewModel.primarySquad {
                        squadHome(squad)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.hooprBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationDestination(for: String.self) { squadId in
                SquadDetailView(viewModel: viewModel, squadId: squadId)
            }
            .sheet(item: $creating) { _ in
                CreateSquadSheet(
                    viewModel: viewModel,
                    onCreated: { _ in creating = nil },
                    onCancel: { creating = nil }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Seasons")
                .hooprFont(28, weight: .bold, maximumSize: 40)
                .foregroundStyle(Color.hooprPrimaryText)

            Spacer(minLength: 8)

            ProfileButton(friendService: friendService, action: onOpenProfile)
                .offset(x: 8)
        }
        .padding(.top, 8)
    }

    private var loading: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Screen 1: no squad

    /// A hero, not an error. Someone with no squad hasn't failed at anything —
    /// they've arrived at a feature they haven't used, and the screen's job is
    /// to say what it's for in one sentence.
    private var emptyState: some View {
        VStack(spacing: 14) {
            SquadCrest(
                iconKey: Squad.defaultIconKey,
                colorKey: Squad.defaultColorKey,
                size: SquadCrest.Size.hero
            )
            .padding(.top, 24)

            Text("Play a season")
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Form a squad, queue for 3v3 matches against other squads nearby, and build a record that actually means something.")
                .hooprFont(15)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                creating = CreateRoute()
            } label: {
                Text("Create a squad")
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprOnBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.hooprOrange)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    // MARK: - Screen 2: squad home

    @ViewBuilder
    private func squadHome(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                path.append(squad.id)
            } label: {
                squadHeader(squad)
            }
            .buttonStyle(.plain)

            matchmakingCard

            rosterCard(squad)

            // More than one squad is legal — the schema doesn't stop it — so
            // the others get rows rather than being silently dropped by
            // `primarySquad`.
            if viewModel.squads.count > 1 {
                otherSquads(besides: squad)
            }

            Button {
                creating = CreateRoute()
            } label: {
                Text("Create another squad")
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .buttonStyle(.plain)
        }
    }

    private func squadHeader(_ squad: Squad) -> some View {
        HStack(spacing: 14) {
            SquadCrest(squad: squad, size: SquadCrest.Size.hero)

            VStack(alignment: .leading, spacing: 4) {
                Text(squad.name)
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)

                Text("\(squad.format.displayName) · \(squad.region)")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)

                // The record is a *query* over confirmed games, not a stored
                // counter (plan §1.1). There are no season games yet, so this
                // says so rather than rendering a 0–0 that looks like a real
                // result.
                Text("No games played yet")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .hooprFont(14, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .padding(16)
        .cardChrome()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens squad details")
    }

    /// The honest empty state the plan asks for: what this space is going to
    /// hold, and that it doesn't hold it yet.
    private var matchmakingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matchmaking is coming")
                .hooprFont(16, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Queueing your squad against another one isn't built yet. For now, get your roster together — you'll be ready the day it lands.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    private func rosterCard(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Roster")
                    .hooprFont(13, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .textCase(.uppercase)

                Spacer()

                Text(squad.rosterText)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            ForEach(viewModel.members(of: squad)) { member in
                SquadMemberRow(member: member)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    @ViewBuilder
    private func otherSquads(besides primary: Squad) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your other squads")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            ForEach(viewModel.squads.filter { $0.id != primary.id }) { squad in
                Button {
                    path.append(squad.id)
                } label: {
                    HStack(spacing: 12) {
                        SquadCrest(squad: squad, size: SquadCrest.Size.row)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(squad.name)
                                .hooprFont(15, weight: .semibold)
                                .foregroundStyle(Color.hooprPrimaryText)
                            Text(squad.rosterText)
                                .hooprFont(13)
                                .foregroundStyle(Color.hooprSecondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .hooprFont(13, weight: .semibold)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                    .padding(12)
                    .cardChrome(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Invites

    /// Where an invite lands. Not one of the plan's numbered screens, and
    /// necessary: the leader can invite from screen 9, but without somewhere to
    /// *answer* an invite the roster can never gain a second member, which is
    /// the only thing the self-join rule exists for.
    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Squad invites")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            ForEach(viewModel.incomingInvites) { row in
                inviteRow(row)
            }
        }
    }

    private func inviteRow(_ row: SquadViewModel.IncomingInvite) -> some View {
        HStack(spacing: 12) {
            if let squad = row.squad {
                SquadCrest(squad: squad, size: SquadCrest.Size.card)
            } else {
                SquadCrest(
                    iconKey: Squad.defaultIconKey,
                    colorKey: Squad.defaultColorKey,
                    size: SquadCrest.Size.card
                )
                .redacted(reason: .placeholder)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.squadName)
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text(row.squad.map { "\($0.format.displayName) · \($0.rosterText)" } ?? "Invited you to join")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Join") {
                    Task { await viewModel.acceptInvite(row.invite) }
                }
                .buttonStyle(.plain)
                .hooprFont(14, weight: .semibold)
                .foregroundStyle(Color.hooprOnBrand)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.hooprOrange))

                Button("Decline") {
                    Task { await viewModel.declineInvite(row.invite) }
                }
                .buttonStyle(.plain)
                .hooprFont(14)
                .foregroundStyle(Color.hooprRed)
            }
            .disabled(viewModel.isBlocked(row.id))
        }
        .padding(12)
        .cardChrome(cornerRadius: 12)
    }
}

/// One person on a roster, or one person the leader could invite.
///
/// Shared by squad home and the detail screen so a member reads identically in
/// both — the role `FriendRow` plays on the friends list.
struct SquadMemberRow: View {
    let member: SquadViewModel.MemberRow

    /// A control on the trailing edge — "Invite", or the leader's badge.
    var trailing: AnyView?

    init(member: SquadViewModel.MemberRow, trailing: AnyView? = nil) {
        self.member = member
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(initial: member.initial, diameter: 34)

            VStack(alignment: .leading, spacing: 2) {
                if member.isResolved {
                    Text(member.displayName)
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                } else {
                    // A skeleton rather than "Unknown player": the name is a
                    // decoration on a membership that's already real.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.hooprFill)
                        .frame(width: 120, height: 14)
                }

                if member.isLeader {
                    Text("Leader")
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                trailing
            }
        }
    }
}
