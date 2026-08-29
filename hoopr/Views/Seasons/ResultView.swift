import SwiftUI

/// Screen 8 — result. "Who won?" as two large crest buttons, an optional score,
/// then a waiting / confirmed / *"results don't match"* state.
///
/// **The three states are derived, not chosen.** Everything below reads
/// `SeasonGame.reportOutcome`, which is the same derivation the rules perform
/// over the same two fields — so the screen can never show a match as confirmed
/// that the server considers disputed, or the other way round.
struct ResultView: View {
    @StateObject private var viewModel: ResultViewModel

    /// Kept as strings because the field is optional and empty has to mean
    /// "didn't say", not zero. Plan §5 calls the score cosmetic, and it is —
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        onRetry: nil,
                        onDismiss: { viewModel.dismissError() }
                    )
                }

                outcomeCard

                if viewModel.canReport {
                    whoWonCard
                    scoreCard
                }
            }
            .padding(16)
        }
        .background(Color.hooprBackground)
        .navigationTitle("Result")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Where the match stands

    @ViewBuilder
    private var outcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.outcome {
            case .confirmed(let winnerId):
                confirmedState(winnerId)
            case .disputed:
                disputedState
            case .awaitingReport:
                awaitingState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    private func confirmedState(_ winnerId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(winnerId == viewModel.mySquadId ? "You won" : "\(viewModel.name(of: winnerId)) won")
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Both leaders reported the same result, so it counts. It's on both squads' records now.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let score = scoreLine {
                Text(score)
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .monospacedDigit()
            }
        }
    }

    /// Not a failure banner. A disagreement is a designed outcome — the match
    /// counts for nobody until the two of them sort it out, which is what
    /// actually happens at a court.
    private var disputedState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results don't match")
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text(disputeDetail)
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Nobody's record moves until you agree. Talk it over and whoever's wrong can report again.")
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disputeDetail: String {
        guard let mine = viewModel.myReport, let theirs = viewModel.opponentReport else {
            return "The two squads reported different winners."
        }
        return "You said \(viewModel.name(of: mine)) won. \(viewModel.opponentName) said \(viewModel.name(of: theirs)) won."
    }

    @ViewBuilder
    private var awaitingState: some View {
        if let mine = viewModel.myReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting on \(viewModel.opponentName)")
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("You reported \(viewModel.name(of: mine)) as the winner. It counts once their leader agrees.")
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if viewModel.isTooEarly {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not played yet")
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("You can record the result once tip-off has passed.")
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if viewModel.isLeader {
            VStack(alignment: .leading, spacing: 8) {
                Text("How'd it go?")
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("Both leaders report who won. A result counts once you agree — which is what makes a record worth something.")
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            // A roster member, not a leader. They see the state and whose move
            // it is, rather than a control that would be refused server-side.
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting on the leaders")
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text("Each squad's leader reports who won, and the result counts once they agree.")
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoreLine: String? {
        guard let home = viewModel.game.homeScore, let away = viewModel.game.awayScore else {
            return nil
        }
        return "\(viewModel.name(of: viewModel.game.homeSquadId)) \(home) – \(away) \(viewModel.name(of: viewModel.game.awaySquadId))"
    }

    // MARK: - Who won?

    private var whoWonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.myReport == nil ? "Who won?" : "Change your answer")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                winnerButton(viewModel.game.homeSquadId)
                winnerButton(viewModel.game.awaySquadId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    private func winnerButton(_ squadId: String) -> some View {
        let isChosen = viewModel.myReport == squadId
        let name = viewModel.name(of: squadId)

        return Button {
            Task {
                await viewModel.report(
                    winner: squadId,
                    homeScore: Self.score(homeScoreText),
                    awayScore: Self.score(awayScoreText)
                )
            }
        } label: {
            VStack(spacing: 10) {
                if let squad = viewModel.squad(id: squadId) {
                    SquadCrest(squad: squad, size: SquadCrest.Size.hero)
                } else {
                    SquadCrest(
                        iconKey: Squad.defaultIconKey,
                        colorKey: Squad.defaultColorKey,
                        size: SquadCrest.Size.hero
                    )
                    .redacted(reason: .placeholder)
                }

                Text(name)
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.center)

                Text(isChosen ? "Your pick" : "Won")
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isChosen ? Color.hooprFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isChosen ? Color.hooprOrange : Color.hooprBorder,
                        lineWidth: isChosen ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isReporting)
        // The crest is decorative and the label carries the meaning, so the
        // whole button reads as one thing rather than announcing a squad twice.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) won")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - The optional score

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isScoring.toggle()
            } label: {
                HStack {
                    Text(isScoring ? "Score" : "Add the score (optional)")
                        .hooprFont(14, weight: .semibold)
                        .foregroundStyle(Color.hooprSecondaryText)

                    Spacer(minLength: 0)

                    Image(systemName: isScoring ? "chevron.up" : "chevron.down")
                        .hooprFont(12, weight: .semibold)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .buttonStyle(.plain)

            if isScoring {
                HStack(spacing: 12) {
                    scoreField(
                        label: viewModel.name(of: viewModel.game.homeSquadId),
                        text: $homeScoreText
                    )
                    scoreField(
                        label: viewModel.name(of: viewModel.game.awaySquadId),
                        text: $awayScoreText
                    )
                }

                Text("The score is for the two of you to look back on. Only who won moves a record.")
                    .hooprFont(12)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardChrome()
    }

    private func scoreField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .hooprFont(12)
                .foregroundStyle(Color.hooprSecondaryText)
                .lineLimit(1)

            TextField("—", text: text)
                .hooprFont(17, weight: .semibold)
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
