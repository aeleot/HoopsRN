import SwiftUI

/// Squad detail — plan §5, screen 9.
///
/// Record, form guide, full game history, roster, leader controls, and the
/// invite picker.
///
/// Takes the tab's `SquadViewModel` rather than building its own. The squad is
/// looked up by ID on every render for the same reason `FriendsViewModel`'s
/// rows are re-derived from live state: a member joining or the leader
/// disbanding has to reach this screen, and a squad captured at push time
/// would freeze both. The record is the same idea one collection over — it is a
/// *query* over confirmed matches, so it moves the moment a result is
/// confirmed, with nothing to invalidate.
struct SquadDetailView: View {
    @ObservedObject var viewModel: SquadViewModel
    let squadId: String

    /// The matches this squad has played. Observed so a result confirmed from
    /// screen 8 moves the record here without a re-push.
    @ObservedObject var seasonGameService: SeasonGameService

    /// Screen 8, for a match still waiting on this squad's report.
    let onOpenResult: (SeasonGame) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isInviting = false
    @State private var confirmingLeave = false
    @State private var confirmingDisband = false

    private var squad: Squad? { viewModel.squad(id: squadId) }

    private var isLeader: Bool {
        squad?.isLeader(viewModel.currentUserId) ?? false
    }

    var body: some View {
        ScrollView {
            if let squad {
                VStack(alignment: .leading, spacing: 16) {
                    crestHeader(squad)
                    recordCard
                    historyCard
                    rosterCard(squad)

                    if isLeader {
                        invitesCard(squad)
                    }

                    controls(squad)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            } else {
                // The listener stopped carrying this squad — it was disbanded,
                // or the caller left it — which is a normal end for this screen
                // rather than a failure.
                goneState
            }
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(squad?.name ?? "Squad")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header

    private func crestHeader(_ squad: Squad) -> some View {
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
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .cardChrome()
    }

    // MARK: - Record and form

    private var record: SeasonGame.Record { seasonGameService.record(for: squadId) }

    private var form: [SeasonGame.Outcome] { seasonGameService.form(for: squadId) }

    /// The record, derived from confirmed `seasonGames` (plan §1.1) rather than
    /// stored on the squad. Two integers and the last five results — the
    /// cheapest way to make a record feel like a season.
    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            if record.isUnplayed {
                Text("No games played yet")
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("A squad's W‑L comes from games both leaders confirmed, so it starts with your first result.")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(record.displayText)
                    .hooprFont(28, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .monospacedDigit()

                FormGuide(form: form)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    // MARK: - History

    /// Every match this squad has, most recent first — the plan's "full game
    /// history".
    ///
    /// Not filtered to confirmed results: a disputed match and a cancelled one
    /// are both things a squad needs to see, and a match still waiting on this
    /// squad's report is the row that carries the way to record it.
    private var history: [SeasonGame] {
        seasonGameService.games(for: squadId)
            .sorted { $0.scheduledTime > $1.scheduledTime }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game history")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            if history.isEmpty {
                // A sentence rather than a blank list. Nothing has failed —
                // this squad simply hasn't played yet, which is a different
                // thing from a history that wouldn't load.
                Text(
                    seasonGameService.hasLoadedGames
                        ? "No matches yet. Queue up and your results will collect here."
                        : "Loading your matches…"
                )
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(history) { game in
                    historyRow(game)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    @ViewBuilder
    private func historyRow(_ game: SeasonGame) -> some View {
        Button {
            onOpenResult(game)
        } label: {
            HStack(spacing: 12) {
                outcomeBadge(game)

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.opponentName(of: squadId) ?? "Opponent")
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .multilineTextAlignment(.leading)

                    Text(historyDetail(game))
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                Spacer(minLength: 8)

                if game.status != .cancelled {
                    Image(systemName: "chevron.right")
                        .hooprFont(12, weight: .semibold)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(game.status == .cancelled)
        .accessibilityElement(children: .combine)
    }

    private func historyDetail(_ game: SeasonGame) -> String {
        let date = game.scheduledTime.formatted(.dateTime.month(.abbreviated).day())

        switch game.status {
        case .cancelled:
            return "\(date) · Cancelled"
        case .disputed:
            return "\(date) · Results don't match"
        case .confirmed:
            guard let home = game.homeScore, let away = game.awayScore else { return date }
            let mine = game.isHome(squadId) ? home : away
            let theirs = game.isHome(squadId) ? away : home
            return "\(date) · \(mine)–\(theirs)"
        case .scheduled:
            return game.scheduledTime > Date()
                ? "\(date) · Scheduled"
                : "\(date) · Result not in yet"
        }
    }

    /// W and L read as a result; everything else needs a word, because a match
    /// nobody confirmed is not a loss and must never look like one.
    @ViewBuilder
    private func outcomeBadge(_ game: SeasonGame) -> some View {
        switch game.status {
        case .confirmed where game.result == squadId:
            FormPill(outcome: .win)
        case .confirmed:
            FormPill(outcome: .loss)
        case .disputed:
            neutralBadge("!", label: "Results don't match")
        case .cancelled:
            neutralBadge("–", label: "Cancelled")
        case .scheduled:
            neutralBadge("·", label: "No result yet")
        }
    }

    private func neutralBadge(_ glyph: String, label: String) -> some View {
        Text(glyph)
            .hooprFont(13, weight: .bold)
            .foregroundStyle(Color.hooprSecondaryText)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.hooprFill))
            .accessibilityLabel(label)
    }

    // MARK: - Roster

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

    // MARK: - Invites

    /// The invite picker: friends, minus everyone already on the squad, minus
    /// everyone already asked. That join is `SquadViewModel.invitableUids`, and
    /// it's the reason this feature has a view model at all.
    private func invitesCard(_ squad: Squad) -> some View {
        let invitable = viewModel.invitableFriends(for: squad)
        let pending = viewModel.pendingInvites(for: squad)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Invite friends")
                    .hooprFont(13, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .textCase(.uppercase)

                Spacer()

                if squad.isFull {
                    Text("Roster full")
                        .hooprFont(13)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }

            if !pending.isEmpty {
                ForEach(pending) { invite in
                    pendingInviteRow(invite)
                }
            }

            if squad.isFull {
                Text("This squad has every seat filled. Someone has to leave before you can add anyone.")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if invitable.isEmpty {
                // Two different situations, and they need different sentences —
                // "nobody left to ask" is progress, "no friends yet" is a
                // different screen away.
                Text(
                    viewModel.hasFriends
                        ? "Everyone you're friends with is already on this squad or has an invite waiting."
                        : "Squads are built from your friends. Add some from your profile, then invite them here."
                )
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(isInviting ? invitable : Array(invitable.prefix(Self.collapsedInviteCount))) { friend in
                    SquadMemberRow(
                        member: friend,
                        trailing: AnyView(inviteButton(friend, squad: squad))
                    )
                }

                if invitable.count > Self.collapsedInviteCount {
                    Button(isInviting ? "Show fewer" : "Show all \(invitable.count)") {
                        isInviting.toggle()
                    }
                    .buttonStyle(.plain)
                    .hooprFont(14, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    /// How many invitable friends show before the list asks to be expanded.
    private static let collapsedInviteCount = 5

    private func inviteButton(_ friend: SquadViewModel.MemberRow, squad: Squad) -> some View {
        Button("Invite") {
            Task { await viewModel.invite(friend.uid, to: squad) }
        }
        .buttonStyle(.plain)
        .hooprFont(14, weight: .semibold)
        .foregroundStyle(Color.hooprOnBrand)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.hooprOrange))
        .disabled(viewModel.isBlocked(friend.uid))
    }

    private func pendingInviteRow(_ invite: SquadInvite) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(initial: initial(for: invite.uid), diameter: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(name(for: invite.uid))
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("Invited")
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            Button("Revoke") {
                Task { await viewModel.revokeInvite(invite) }
            }
            .buttonStyle(.plain)
            .hooprFont(14)
            .foregroundStyle(Color.hooprRed)
            .disabled(viewModel.isBlocked(invite.uid))
        }
    }

    private func name(for uid: String) -> String {
        let resolved = viewModel.profilesByUid[uid]?.userName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? "This player" : resolved
    }

    private func initial(for uid: String) -> String {
        guard let first = name(for: uid).first(where: \.isLetter) else { return "" }
        return String(first).uppercased()
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ squad: Squad) -> some View {
        VStack(spacing: 10) {
            if isLeader {
                // Disbanding, not leaving. The self-leave rule refuses a leader
                // server-side, so offering "Leave" here would produce a
                // `permission-denied` nobody could act on.
                Button("Disband squad") { confirmingDisband = true }
                    .buttonStyle(.plain)
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.hooprFill))
            } else if squad.canLeave(viewModel.currentUserId) {
                Button("Leave squad") { confirmingLeave = true }
                    .buttonStyle(.plain)
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.hooprFill))
            }
        }
        .confirmationDialog(
            "Disband \(squad.name)?",
            isPresented: $confirmingDisband,
            titleVisibility: .visible
        ) {
            Button("Disband", role: .destructive) {
                Task {
                    await viewModel.disband(squad)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone on the roster loses the squad. This can't be undone.")
        }
        .confirmationDialog(
            "Leave \(squad.name)?",
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    await viewModel.leave(squad)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need a new invite from the leader to come back.")
        }
    }

    private var goneState: some View {
        VStack(spacing: 10) {
            Text("This squad is gone")
                .hooprFont(18, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("It was disbanded, or you're no longer on it.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
