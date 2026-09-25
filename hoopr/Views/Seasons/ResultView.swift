import SwiftUI

/// The result screen. "Who won?" as two large crest buttons, an optional score,
/// then a waiting / confirmed / *"results don't match"* state.
///
/// **The three states are derived, not chosen.** Everything below reads
/// `SeasonGame.reportOutcome`, which is the same derivation the rules perform
/// over the same two fields — so the screen can never show a match as confirmed
/// that the server considers disputed, or the other way round.
///
/// **Redesigned in UI revamp Phase 2b**. The
/// screen that delivers the app's one trustworthy number set "You won" at 22pt
/// inside a card, over a page that was otherwise empty. Now the outcome is the
/// band's display line (`ResultBand`) — the winner's crest above it and the
/// score as numerals when one was entered — and reporting is one question with
/// one control: "Who won?" over two large crest buttons (`WinnerButton`). The
/// band carries the back button, as squad detail's does.
///
/// **What the copy may not do** (`gaps/SEASONS.md`), and `ResultCopyTests`
/// holds it to: a match awaiting the other leader **waits forever** — there is
/// no timeout, forfeit or nudge — so nothing may imply one is coming; and a
/// dispute is a *designed* outcome, never drawn as an error.
///
/// **Never exercised on two real devices**, so its live rendering is unseen.
/// The band and the buttons take plain values and are rendered off-device.
struct ResultView: View {
    @StateObject private var viewModel: ResultViewModel

    @Environment(\.dismiss) private var dismiss

    /// Kept as strings because the field is optional and empty has to mean
    /// "didn't say", not zero. The score is cosmetic —
    /// nothing here feeds the record.
    @State private var homeScoreText = ""
    @State private var awayScoreText = ""
    @State private var isScoring = false

    init(
        game: SeasonGame,
        mySquadId: String,
        seasonGameService: SeasonGameService,
        squadService: SquadService
    ) {
        _viewModel = StateObject(wrappedValue: ResultViewModel(
            game: game,
            mySquadId: mySquadId,
            seasonGameService: seasonGameService,
            squadService: squadService
        ))
    }

    private var game: SeasonGame { viewModel.game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultBand(
                    matchup: "\(viewModel.myName) vs \(viewModel.opponentName)",
                    copy: copy,
                    winner: winner,
                    score: score
                )

                VStack(alignment: .leading, spacing: Spacing.section) {
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            onRetry: nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                    }

                    if viewModel.canReport {
                        whoWon
                        scoreSection
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .hooprStatusBarScrim()
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Your squad's win, once (UI revamp Phase 5). Over everything, down to
        // the status bar, and it takes no touch — the screen under it works
        // while it falls. Whether to fire is the view model's call.
        .overlay {
            if let celebration = viewModel.celebration {
                ConfettiBurst(
                    colors: confettiColors,
                    seed: Confetti.seed(for: celebration.gameId),
                    onFinished: { viewModel.celebrationFinished() }
                )
                .ignoresSafeArea()
            }
        }
        // The band carries the back button, as squad detail's does. See
        // `BandBackButton`. The title stays for VoiceOver.
        .navigationTitle("Result")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - Where the match stands

    private var copy: ResultCopy.Text {
        ResultCopy.text(
            outcome: viewModel.outcome,
            mySquadId: viewModel.mySquadId,
            myReport: viewModel.myReport,
            opponentReport: viewModel.opponentReport,
            opponentName: viewModel.opponentName,
            isTooEarly: viewModel.isTooEarly,
            isLeader: viewModel.isLeader,
            name: { viewModel.name(of: $0) }
        )
    }

    /// The winning squad's crest, drawn over "You won" once it's confirmed —
    /// the one place the crest colour stands for something that happened
    /// rather than for who you are.
    private var winner: ResultBand.Winner? {
        guard case .confirmed(let winnerId) = viewModel.outcome else { return nil }
        return ResultBand.Winner(squad: viewModel.squad(id: winnerId))
    }

    /// The winner's own colour, twice so it leads, then the brand's orange and
    /// gold. Only a win of *yours* is celebrated, so the crest is this squad's.
    private var confettiColors: [Color] {
        let crest = Color.hooprSquad(viewModel.squad(id: viewModel.mySquadId)?.colorKey ?? Squad.defaultColorKey)
        return [crest, crest, .hooprOrange, .hooprSquad("gold")]
    }

    /// This squad's score first, as squad detail's history reads it.
    private var score: ResultBand.Score? {
        guard case .confirmed = viewModel.outcome,
              let home = game.homeScore, let away = game.awayScore
        else { return nil }
        let isHome = game.isHome(viewModel.mySquadId)
        return ResultBand.Score(
            mine: isHome ? home : away,
            theirs: isHome ? away : home,
            myName: viewModel.myName,
            theirName: viewModel.opponentName
        )
    }

    // MARK: - Who won?

    /// One question, one control (archetype A5): the question at the title
    /// size, centred, and the two crests as the answer.
    private var whoWon: some View {
        VStack(spacing: Spacing.lg) {
            Text(viewModel.myReport == nil ? "Who won?" : "Change your answer")
                .hooprType(.title)
                .foregroundStyle(Color.hooprPrimaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: Spacing.md) {
                winnerButton(game.homeSquadId)
                winnerButton(game.awaySquadId)
            }
        }
    }

    private func winnerButton(_ squadId: String) -> some View {
        WinnerButton(
            squad: viewModel.squad(id: squadId),
            name: viewModel.name(of: squadId),
            isChosen: viewModel.myReport == squadId,
            isBusy: viewModel.isReporting
        ) {
            Task {
                await viewModel.report(
                    winner: squadId,
                    homeScore: Self.score(homeScoreText),
                    awayScore: Self.score(awayScoreText)
                )
            }
        }
    }

    // MARK: - The optional score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                isScoring.toggle()
            } label: {
                HStack {
                    Text(isScoring ? "Score" : "Add the score (optional)")
                        .hooprType(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprSecondaryText)

                    Spacer(minLength: 0)

                    Image(systemName: isScoring ? "chevron.up" : "chevron.down")
                        .hooprFont(13, weight: .semibold, maximumSize: 18)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isScoring {
                HStack(spacing: Spacing.md) {
                    scoreField(
                        label: viewModel.name(of: game.homeSquadId),
                        text: $homeScoreText
                    )
                    scoreField(
                        label: viewModel.name(of: game.awaySquadId),
                        text: $awayScoreText
                    )
                }

                // The report is sent by the crest tap, with whatever score is
                // in these fields at that moment. A score typed after the tap
                // was silently not sent; this says so where it's typed.
                Text("Your score is sent with your pick, so enter it before you tap the winner, or tap them again after. Only who won moves a record.")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scoreField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .lineLimit(1)

            TextField("—", text: text, prompt: .hooprPrompt("—"))
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.hooprFill))
                .accessibilityLabel("\(label) score")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Empty means "didn't say", which is why this is an optional rather than a
    /// zero — the rules accept the field being absent and a stored 0 would read
    /// as a shutout nobody claimed.
    private static func score(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }
}

// MARK: - The copy

/// What the band says in each state, as one pure function so the two rules the
/// screen can't show on one device are testable: **no deadline** while waiting
/// on the other leader, and a dispute that reads as a disagreement rather than
/// a failure. The wording is the screen's existing copy, moved, not rewritten.
nonisolated enum ResultCopy {
    struct Text: Equatable {
        let headline: String
        let body: [String]
    }

    static func text(
        outcome: SeasonGame.ReportOutcome,
        mySquadId: String,
        myReport: String?,
        opponentReport: String?,
        opponentName: String,
        isTooEarly: Bool,
        isLeader: Bool,
        name: (String) -> String
    ) -> Text {
        switch outcome {
        case .confirmed(let winnerId):
            return Text(
                headline: winnerId == mySquadId ? "You won" : "\(name(winnerId)) won",
                body: ["Both leaders reported the same result, so it counts. It's on both squads' records now."]
            )

        case .disputed:
            let detail: String
            if let mine = myReport, let theirs = opponentReport {
                detail = "You said \(name(mine)) won. \(opponentName) said \(name(theirs)) won."
            } else {
                detail = "The two squads reported different winners."
            }
            return Text(
                headline: "Results don't match",
                body: [detail, "Nobody's record moves until you agree. Talk it over and whoever's wrong can report again."]
            )

        case .awaitingReport:
            if let mine = myReport {
                return Text(
                    headline: "Waiting on \(opponentName)",
                    body: ["You reported \(name(mine)) as the winner. It counts once their leader agrees."]
                )
            } else if isTooEarly {
                return Text(
                    headline: "Not played yet",
                    body: ["You can record the result once tip-off has passed."]
                )
            } else if isLeader {
                return Text(
                    headline: "How'd it go?",
                    body: ["Both leaders report who won. A result counts once you agree — which is what makes a record worth something."]
                )
            } else {
                // A roster member, not a leader. They see the state and whose
                // move it is, rather than a control that would be refused.
                return Text(
                    headline: "Waiting on the leaders",
                    body: ["Each squad's leader reports who won, and the result counts once they agree."]
                )
            }
        }
    }
}

// MARK: - The band

/// The result's hero: the outcome at `display`, the winner's crest above it and
/// the score as numerals when there are both, then what it means.
///
/// **Neutral, like every band** — the brief asked for the winning crest's
/// colour as the ground, and the Seasons tab measured that no tint strong
/// enough to read as a squad's colour keeps the band's text at AA. So the
/// colour is the crest itself, full-strength at the hero size.
///
/// A dispute is drawn exactly like any other state: primary text, no red, no
/// warning glyph. It is a disagreement the design expects, not an error.
struct ResultBand: View {
    struct Winner {
        /// `nil` while the crest is still loading; drawn as a placeholder.
        let squad: Squad?
    }

    struct Score {
        let mine: Int
        let theirs: Int
        let myName: String
        let theirName: String
    }

    let matchup: String
    let copy: ResultCopy.Text
    var winner: Winner?
    var score: Score?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            BandBackButton()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(matchup)
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let winner {
                    Group {
                        if let squad = winner.squad {
                            SquadCrest(squad: squad, size: SquadCrest.Size.hero)
                        } else {
                            SquadCrest(
                                iconKey: Squad.defaultIconKey,
                                colorKey: Squad.defaultColorKey,
                                size: SquadCrest.Size.hero
                            )
                            .redacted(reason: .placeholder)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityHidden(true)
                }

                SwiftUI.Text(copy.headline)
                    .hooprType(.display)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let score {
                    scoreboard(score)
                }

                ForEach(copy.body, id: \.self) { line in
                    SwiftUI.Text(line)
                        .hooprType(.body)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, ProfileButton.Slot.top)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.hooprHeroBand.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    /// "21 – 15" as numerals, each number over the squad it belongs to, this
    /// squad first.
    private func scoreboard(_ score: Score) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            side(score.mine, score.myName)
            SwiftUI.Text("–")
                .hooprType(.numeral)
                .foregroundStyle(Color.hooprSecondaryText)
            side(score.theirs, score.theirName)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score.myName) \(score.mine), \(score.theirName) \(score.theirs)")
    }

    private func side(_ points: Int, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SwiftUI.Text("\(points)")
                .hooprType(.numeral)
                .foregroundStyle(Color.hooprPrimaryText)
            SwiftUI.Text(name)
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The answer

/// One of the two answers to "Who won?": the squad's crest, large, over its
/// name. The only place a `SquadCrest` is the control rather than decoration
/// (`UI_SHELL.md`), so it keeps its explicit label.
///
/// **The unchosen edge is `hooprSeparatorStrong`, at 3:1.** It was the faint
/// `hooprBorder` hairline (1.2:1 on white), under the floor WCAG 1.4.11 sets
/// for the boundary of a control — on the one screen where the two controls
/// are the whole point.
struct WinnerButton: View {
    let squad: Squad?
    let name: String
    let isChosen: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Group {
                    if let squad {
                        SquadCrest(squad: squad, size: SquadCrest.Size.hero)
                    } else {
                        SquadCrest(
                            iconKey: Squad.defaultIconKey,
                            colorKey: Squad.defaultColorKey,
                            size: SquadCrest.Size.hero
                        )
                        .redacted(reason: .placeholder)
                    }
                }

                Text(name)
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if isChosen {
                    Text("Your pick")
                        .hooprType(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprBrandAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isChosen ? Color.hooprFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isChosen ? Color.hooprBrandAccent : Color.hooprSeparatorStrong,
                        lineWidth: isChosen ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.hooprPress)
        .disabled(isBusy)
        // The crest is decorative and the label carries the meaning, so the
        // whole button reads as one thing rather than announcing a squad twice.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) won")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}
