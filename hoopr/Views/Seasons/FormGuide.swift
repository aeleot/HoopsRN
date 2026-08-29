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

/// One result. Sized to stay a circle rather than an ellipse as text grows,
/// which is why the letter is the only thing that scales.
struct FormPill: View {
    let outcome: SeasonGame.Outcome

    var body: some View {
        Text(outcome.rawValue)
            .hooprFont(13, weight: .bold, maximumSize: 17)
            .foregroundStyle(outcome == .win ? Color.hooprOnBrand : Color.hooprSecondaryText)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(outcome == .win ? Color.hooprOrange : Color.hooprFill)
            )
            .accessibilityLabel(outcome == .win ? "Win" : "Loss")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        FormGuide(form: [.win, .win, .loss, .win, .loss])
        FormGuide(form: [.loss])
    }
    .padding()
    .background(Color.hooprBackground)
}
