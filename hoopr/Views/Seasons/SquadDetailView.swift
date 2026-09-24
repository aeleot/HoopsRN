import SwiftUI

/// Squad detail — one squad's roster, invites and season history.
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
///
/// **Redesigned in UI revamp Phase 2b**. It was
/// the card-stack pattern at its limit: six `cardChrome()` blocks in one
/// column, each under its own uppercase label, nothing on the screen larger
/// than 22pt, and the record at 28pt inside the second card. Now it opens on
/// the band squad home ends on (`SquadIdentity` and `SquadRecordLine`, shared),
/// so the push reads as a continuation. Under it, the history and the roster
/// are rows under labels, and Leave / Disband sit quietly at the bottom.
struct SquadDetailView: View {
    @ObservedObject var viewModel: SquadViewModel
    let squadId: String

    /// The matches this squad has played. Observed so a result confirmed from
    /// the result screen moves the record here without a re-push.
    @ObservedObject var seasonGameService: SeasonGameService

    /// The result screen, for a match still waiting on this squad's report.
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
                VStack(alignment: .leading, spacing: 0) {
                    band(squad)

                    VStack(alignment: .leading, spacing: Spacing.section) {
                        // The tab's banner is behind this screen, so an invite
                        // or a revoke that failed here would otherwise fail
                        // silently. Same view model, same message.
                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(
                                message: errorMessage,
                                onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                                onDismiss: { viewModel.dismissError() }
                            )
                        }

                        historySection
                        rosterSection(squad)

                        if isLeader {
                            invitesSection(squad)
                        }

                        controls(squad)
                    }
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.top, Spacing.xxl)
                    .padding(.bottom, Spacing.xxxl)
                }
            } else {
                // The listener stopped carrying this squad — it was disbanded,
                // or the caller left it — which is a normal end for this screen
                // rather than a failure.
                goneState
            }
        }
        .hooprStatusBarScrim()
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The band carries the back button, so the bar is hidden and the band
        // starts at the safe area, as the Seasons tab's does. See
        // `BandBackButton`. The title stays for VoiceOver.
        .navigationTitle(squad?.name ?? "Squad")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - The band

    /// The same band squad home has — crest, name, record, dots — so the push
    /// reads as a continuation. Built the way the tab's is: it
    /// starts at the safe area, and its first row holds the back button where
    /// the tab's holds its label and the profile button.
    private func band(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            BandBackButton()

            SquadIdentity(squad: squad)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

            SquadRecordLine(record: record, form: form)
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, ProfileButton.Slot.top)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The squad's own colour, at the band's luminance (UI revamp Phase 4):
        // which squad this is, before the name is read.
        .background {
            HeroWash(placement: .leading(.hooprSquadWash(squad.colorKey)))
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    private var record: SeasonGame.Record { seasonGameService.record(for: squadId) }

    private var form: [SeasonGame.Outcome] { seasonGameService.form(for: squadId) }

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

    /// A board of rows under one label (archetype A2), not a card.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Game history")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            if history.isEmpty {
                // A sentence rather than a blank list. Nothing has failed —
                // this squad simply hasn't played yet, which is a different
                // thing from a history that wouldn't load. It also carries
                // what the record card used to explain: why the record starts
                // at the first *confirmed* result.
                Text(
                    seasonGameService.hasLoadedGames
                        ? "No matches yet. Results both leaders confirm collect here and count toward your record."
                        : "Loading your matches…"
                )
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, game in
                        if index > 0 {
                            Divider().overlay(Color.hooprBorder)
                        }
                        SquadHistoryRow(
                            game: game,
                            squadId: squadId,
                            uid: viewModel.currentUserId,
                            onOpen: { onOpenResult(game) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Roster

    /// Members, then anyone invited and not yet answered. An invite is a seat
    /// being offered, so it reads as part of the roster rather than as a
    /// separate card further down.
    private func rosterSection(_ squad: Squad) -> some View {
        let pending = isLeader ? viewModel.pendingInvites(for: squad) : []

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Roster")
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)

                Spacer()

                Text(squad.rosterText)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.members(of: squad).enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        Divider().overlay(Color.hooprBorder)
                    }
                    SquadMemberRow(member: member)
                        .padding(.vertical, Spacing.sm)
                }

                ForEach(pending) { invite in
                    Divider().overlay(Color.hooprBorder)
                    pendingInviteRow(invite)
                        .padding(.vertical, Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingInviteRow(_ invite: SquadInvite) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(initial: initial(for: invite.uid), diameter: PlayerAvatar.Size.roster)

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
            .hooprType(.body)
            .foregroundStyle(Color.hooprRed)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(viewModel.isBlocked(invite.uid))
        }
    }

    // MARK: - Invites

    /// The invite picker: friends, minus everyone already on the squad, minus
    /// everyone already asked. That join is `SquadViewModel.invitableUids`, and
    /// it's the reason this feature has a view model at all.
    private func invitesSection(_ squad: Squad) -> some View {
        let invitable = viewModel.invitableFriends(for: squad)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Invite friends")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            if squad.isFull {
                Text("Every seat is filled. Someone has to leave before you can add anyone.")
                    .hooprType(.body)
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
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                let shown = isInviting ? invitable : Array(invitable.prefix(Self.collapsedInviteCount))

                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 {
                            Divider().overlay(Color.hooprBorder)
                        }
                        SquadMemberRow(
                            member: friend,
                            trailing: AnyView(inviteButton(friend, squad: squad))
                        )
                        .padding(.vertical, Spacing.xs)
                    }
                }

                if invitable.count > Self.collapsedInviteCount {
                    Button(isInviting ? "Show fewer" : "Show all \(invitable.count)") {
                        isInviting.toggle()
                    }
                    .buttonStyle(.plain)
                    .hooprType(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How many invitable friends show before the list asks to be expanded.
    private static let collapsedInviteCount = 5

    /// `compact`: drawn at its label's size inside the full 44pt target, so a
    /// row of them stays compact without shrinking what a thumb has to hit.
    private func inviteButton(_ friend: SquadViewModel.MemberRow, squad: Squad) -> some View {
        Button("Invite") {
            Task { await viewModel.invite(friend.uid, to: squad) }
        }
        .buttonStyle(.hooprFilled(.compact))
        .disabled(viewModel.isBlocked(friend.uid))
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

    /// Quiet, and last. Leaving or disbanding is rare and final, and each is
    /// behind a confirmation — so it's a line of red text at the end of the
    /// page, not a filled block competing with the record.
    @ViewBuilder
    private func controls(_ squad: Squad) -> some View {
        Group {
            if isLeader {
                // Disbanding, not leaving. The self-leave rule refuses a leader
                // server-side, so offering "Leave" here would produce a
                // `permission-denied` nobody could act on.
                destructiveButton("Disband squad") { confirmingDisband = true }
            } else if squad.canLeave(viewModel.currentUserId) {
                destructiveButton("Leave squad") { confirmingLeave = true }
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

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .hooprType(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.hooprRed)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// With the bar hidden, this screen has to carry its own way back too.
    private var goneState: some View {
        VStack(spacing: Spacing.sm) {
            BandBackButton()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ProfileButton.Slot.top)
                .padding(.bottom, 44)

            Text("This squad is gone")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("It was disbanded, or you're no longer on it.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.pageMargin)
    }
}

/// One match in squad detail's game history: a dot in the form guide's
/// colours, the opponent, when and what happened in words, and the score when
/// there is one.
///
/// **The outcome is always a word as well as a colour** — "Won", "Lost" — so
/// this list, unlike the band's dots, never relies on colour at all. Anything
/// that isn't a confirmed result takes the grey dot: a match nobody confirmed
/// is not a loss, and must never look like one.
///
/// Its own view, not a method on `SquadDetailView`, so a render harness can
/// draw every status with the real code. On a single device only the empty
/// history can be seen live.
struct SquadHistoryRow: View {
    let game: SeasonGame
    /// Whose side the row is told from.
    let squadId: String
    /// The signed-in user, who may owe this match a report.
    let uid: String?
    let onOpen: () -> Void
    var now: Date = Date()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A cancelled match has no result to open, so it is a plain row rather
    /// than a disabled button. A disabled button dims its label, and this one
    /// dimmed the opponent's name under AA in the render — for a row that
    /// still has to be read.
    var body: some View {
        if game.status == .cancelled {
            content(opens: false)
                .accessibilityElement(children: .combine)
        } else {
            Button(action: onOpen) {
                content(opens: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the result")
        }
    }

    /// **The score moves under the name at the accessibility sizes.** Beside
    /// it, the 20pt headline scales to about 34pt, and at `.accessibility3` it
    /// squeezed "Hoop Dreams" onto two lines and broke "Jan 12 · Won" in the
    /// middle (render, 2026-09-23). In the detail line it reads "Won 21–15".
    private var scoreBesideName: Bool { !dynamicTypeSize.isAccessibilitySize }

    private func content(opens: Bool) -> some View {
        let status = Self.status(for: game, squadId: squadId, uid: uid, now: now)
        let score = Self.score(for: game, squadId: squadId)
        let scoreInDetail = scoreBesideName ? nil : score

        return HStack(alignment: .center, spacing: Spacing.md) {
            FormDot(outcome: Self.outcome(for: game, squadId: squadId))

            VStack(alignment: .leading, spacing: 2) {
                Text(game.opponentName(of: squadId) ?? "Opponent")
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Date, then what happened. A report this leader still owes
                // is the one line in the list that asks for something, so it
                // is the one drawn as a mark.
                Text("\(Self.dateText(game.scheduledTime)) · \(statusText(status))\(scoreInDetail.map { " \($0)" } ?? "")")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if let score, scoreBesideName {
                Text(score)
                    .hooprType(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)
                    .fixedSize()
            }

            if opens {
                Image(systemName: "chevron.right")
                    .hooprFont(13, weight: .semibold, maximumSize: 18)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// The status run inside the detail line: the accent mark, semibold, when
    /// it asks for something, and the line's own secondary colour otherwise.
    private func statusText(_ status: (text: String, isCallToAction: Bool)) -> Text {
        guard status.isCallToAction else { return Text(status.text) }
        return Text(status.text)
            .foregroundStyle(Color.hooprBrandAccent)
            .fontWeight(.semibold)
    }

    /// What happened, in words, from `squadId`'s side — and whether it is
    /// asking `uid` to do something.
    ///
    /// **"Waiting on …" and never a deadline.** A match awaiting one leader's
    /// report waits forever — no timeout, no forfeit (`gaps/SEASONS.md`) — so
    /// nothing here may imply one is coming. `nonisolated static` so every
    /// case is testable without a view.
    nonisolated static func status(
        for game: SeasonGame,
        squadId: String,
        uid: String?,
        now: Date
    ) -> (text: String, isCallToAction: Bool) {
        switch game.status {
        case .cancelled:
            return ("Cancelled", false)
        case .disputed:
            return ("Results don't match", false)
        case .confirmed:
            return (game.result == squadId ? "Won" : "Lost", false)
        case .scheduled:
            guard now >= game.scheduledTime else { return ("Scheduled", false) }
            guard let uid, game.canReport(uid: uid, at: now) else {
                return ("Result not in yet", false)
            }
            guard game.report(by: uid) != nil else { return ("Report the result", true) }
            return ("Waiting on \(game.opponentName(of: squadId) ?? "the other leader")", false)
        }
    }

    /// The dot: a confirmed win or loss, and grey for everything else.
    nonisolated static func outcome(for game: SeasonGame, squadId: String) -> SeasonGame.Outcome? {
        guard game.status == .confirmed, let result = game.result else { return nil }
        return result == squadId ? .win : .loss
    }

    /// "21–15", this squad's score first — only for a confirmed match with a
    /// score entered. A score is optional; the result is not.
    nonisolated static func score(for game: SeasonGame, squadId: String) -> String? {
        guard game.status == .confirmed, let home = game.homeScore, let away = game.awayScore else {
            return nil
        }
        let mine = game.isHome(squadId) ? home : away
        let theirs = game.isHome(squadId) ? away : home
        return "\(mine)–\(theirs)"
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
