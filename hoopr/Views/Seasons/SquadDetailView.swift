import SwiftUI

/// Squad detail — plan §5, screen 9.
///
/// Record, roster, leader controls, and the invite picker. Game history and the
/// form guide are Phase 6's; the space they'll occupy says so rather than
/// rendering an empty list that looks broken.
///
/// Takes the tab's `SquadViewModel` rather than building its own. The squad is
/// looked up by ID on every render for the same reason `FriendsViewModel`'s
/// rows are re-derived from live state: a member joining or the leader
/// disbanding has to reach this screen, and a squad captured at push time
/// would freeze both.
struct SquadDetailView: View {
    @ObservedObject var viewModel: SquadViewModel
    let squadId: String

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

    /// The record is derived from confirmed `seasonGames` (plan §1.1), and
    /// there aren't any yet — so this names what will fill it instead of
    /// showing two zeros that look like a played season.
    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            Text("No games played yet")
                .hooprFont(16, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("A squad's W‑L comes from games both leaders confirmed, so it starts once matchmaking ships.")
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
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
