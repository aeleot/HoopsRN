import SwiftUI

/// The last five confirmed results as five dots: green a win, red a loss, and
/// grey for a game not yet played. That replaced the orange "W" and grey "L"
/// pills at the user's direction (2026-09-22). A squad with two results shows
/// two coloured dots and three grey ones, so the row is always five long.
///
/// Most recent first, from the left, matching `SeasonGame.form(for:in:limit:)`,
/// which is where the ordering is decided and tested. This view draws what it
/// is handed and derives nothing but the padding.
///
/// **Colour isn't the only cue, though by default it is the only one
/// drawn.** Win and loss can't be told apart by lightness alone while both
/// stay readable on the band (measured; see `hooprFormWin`). So:
/// - the record numeral beside the dots says how many of each;
/// - VoiceOver reads the order;
/// - with iOS's *Differentiate Without Color* setting on, each played dot
///   grows to carry a ✓ or ✕.
struct FormGuide: View {
    let form: [SeasonGame.Outcome]

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// How many results the guide shows, and so how many dots it always draws.
    nonisolated static let length = 5

    var body: some View {
        HStack(spacing: FormDotMetrics.spacing) {
            ForEach(Array(Self.slots(for: form).enumerated()), id: \.offset) { _, outcome in
                FormDot(outcome: outcome, isMarked: differentiateWithoutColor)
            }
        }
        // Five dots announced one by one read as five unrelated shapes.
        // Combined, they read as the sentence a sighted user gets from the
        // shape of the row. With no results there is nothing to say that the
        // record beside it hasn't ("No games played yet this season").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenForm(form))
        .accessibilityHidden(form.isEmpty)
    }

    /// `form` as exactly `length` slots, played results first and `nil` for
    /// each game not yet played. A longer `form` is cut to the most recent.
    nonisolated static func slots(for form: [SeasonGame.Outcome]) -> [SeasonGame.Outcome?] {
        let played = form.prefix(length).map { Optional($0) }
        return played + Array(repeating: nil, count: length - played.count)
    }

    /// "Recent form, most recent first: win, loss". The grey slots aren't read.
    /// They are placeholders, and the record already says how many games were
    /// played.
    nonisolated static func spokenForm(_ form: [SeasonGame.Outcome]) -> String {
        let results = form.prefix(length).map { $0 == .win ? "win" : "loss" }
        return "Recent form, most recent first: \(results.joined(separator: ", "))"
    }
}

/// The geometry of a form dot.
///
/// Fixed rather than scaled with Dynamic Type: a dot carries no text, so there
/// is nothing in it to enlarge. The marked size is the exception. When
/// *Differentiate Without Color* puts a ✓ or ✕ inside, the dot grows so the
/// glyph reads. The glyph keeps `.system(size:)`, as `SquadCrest`'s does,
/// because it is locked inside a frame that can't grow.
enum FormDotMetrics {
    static let diameter: CGFloat = 16
    static let markedDiameter: CGFloat = 22
    static let glyphSize: CGFloat = 11
    static let spacing = Spacing.sm
}

/// One slot in the form guide: a win, a loss, or `nil` for not yet played.
struct FormDot: View {
    let outcome: SeasonGame.Outcome?
    /// Draws the ✓ or ✕ inside, for *Differentiate Without Color*.
    var isMarked: Bool = false

    private var diameter: CGFloat {
        isMarked ? FormDotMetrics.markedDiameter : FormDotMetrics.diameter
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                if isMarked, let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: FormDotMetrics.glyphSize, weight: .heavy))
                        .foregroundStyle(Color.hooprOnFormResult)
                }
            }
    }

    private var fill: Color {
        switch outcome {
        case .win: Color.hooprFormWin
        case .loss: Color.hooprFormLoss
        case nil: Color.hooprFormUnplayed
        }
    }

    private var glyph: String? {
        switch outcome {
        case .win: "checkmark"
        case .loss: "xmark"
        case nil: nil
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        FormGuide(form: [.win, .win, .loss, .win, .loss])
        FormGuide(form: [.win, .loss])
        FormGuide(form: [])
        // What *Differentiate Without Color* draws. The environment value is
        // read-only, so the preview draws the dots directly.
        HStack(spacing: FormDotMetrics.spacing) {
            FormDot(outcome: .win, isMarked: true)
            FormDot(outcome: .loss, isMarked: true)
            FormDot(outcome: nil, isMarked: true)
        }
    }
    .padding()
    .background(Color.hooprBackground)
}
