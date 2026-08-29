import SwiftUI

/// The last five confirmed results as W/L pills — plan §5's "cheapest possible
/// way to make a record feel like a season rather than two integers."
///
/// Most recent first, matching `SeasonGame.form(for:in:limit:)`, which is where
/// the ordering is decided and tested. This view draws what it is handed and
/// derives nothing.
struct FormGuide: View {
    let form: [SeasonGame.Outcome]

    var body: some View {
        if !form.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(form.enumerated()), id: \.offset) { _, outcome in
                    FormPill(outcome: outcome)
                }
            }
            // Five circles announced one by one read as five unrelated letters.
            // Combined, they read as the sentence a sighted user gets from the
            // shape of the row.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recent form, most recent first: \(spokenForm)")
        }
    }

    private var spokenForm: String {
        form.map { $0 == .win ? "win" : "loss" }.joined(separator: ", ")
    }
}

/// The geometry both result pills share.
///
/// **The cap is load-bearing, not decoration.** A pill is a fixed-diameter
/// circle, which is exactly the case `Typography` names as needing
/// `maximumSize`: the frame can't grow, so uncapped text at the accessibility
/// sizes renders outside its own circle. `SeasonsAccessibilityTests` measures
/// these three numbers against each other and fails if a letter stops fitting —
/// the neutral pill shipped uncapped in Phase 6 and that test is what found it.
enum ResultPillMetrics {
    static let diameter: CGFloat = 28
    static let fontSize: CGFloat = 13
    static let maximumFontSize: CGFloat = 17
}

/// One confirmed result. W or L, and nothing else means either.
struct FormPill: View {
    let outcome: SeasonGame.Outcome

    var body: some View {
        Text(outcome.rawValue)
            .hooprFont(
                ResultPillMetrics.fontSize,
                weight: .bold,
                maximumSize: ResultPillMetrics.maximumFontSize
            )
            .foregroundStyle(outcome == .win ? Color.hooprOnBrand : Color.hooprSecondaryText)
            .frame(width: ResultPillMetrics.diameter, height: ResultPillMetrics.diameter)
            .background(
                Circle().fill(outcome == .win ? Color.hooprOrange : Color.hooprFill)
            )
            .accessibilityLabel(outcome == .win ? "Win" : "Loss")
    }
}

/// A match with no confirmed result — disputed, cancelled, or still waiting.
///
/// Deliberately *not* a W/L pill and deliberately not coloured like one: a match
/// nobody confirmed is not a loss, and must never look like one at a glance. The
/// glyph is a placeholder for a result rather than a result, so the spoken label
/// carries the whole meaning.
struct NeutralResultPill: View {
    let glyph: String
    let label: String

    var body: some View {
        Text(glyph)
            .hooprFont(
                ResultPillMetrics.fontSize,
                weight: .bold,
                maximumSize: ResultPillMetrics.maximumFontSize
            )
            .foregroundStyle(Color.hooprSecondaryText)
            .frame(width: ResultPillMetrics.diameter, height: ResultPillMetrics.diameter)
            .background(Circle().fill(Color.hooprFill))
            .accessibilityLabel(label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        FormGuide(form: [.win, .win, .loss, .win, .loss])
        FormGuide(form: [.loss])
        HStack(spacing: 6) {
            NeutralResultPill(glyph: "!", label: "Results don't match")
            NeutralResultPill(glyph: "–", label: "Cancelled")
            NeutralResultPill(glyph: "·", label: "No result yet")
        }
    }
    .padding()
    .background(Color.hooprBackground)
}
