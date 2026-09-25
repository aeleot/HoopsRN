import SwiftUI

/// The squad's crest, name, and format · region — the top of the band on both
/// squad home and squad detail.
///
/// **One view so the push reads as a continuation**: tapping the squad on the
/// Seasons tab opens a screen whose band starts
/// with exactly what was tapped, at the same size, in the same place. Phase 3's
/// `matchedGeometryEffect` will join the two; this is what makes that possible.
struct SquadIdentity: View {
    let squad: Squad
    /// The chevron on squad home, where the row opens squad detail. The detail
    /// screen is where it goes, so it draws none.
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            SquadCrest(squad: squad, size: SquadCrest.Size.hero)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(squad.name)
                    .hooprType(.title)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(squad.format.displayName) · \(squad.region)")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .hooprFont(14, weight: .semibold, maximumSize: 20)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
    }
}

/// The record as the band's numeral, with the last five results as dots pinned
/// to the band's bottom-right corner.
///
/// **The record, set as a scoreboard.** It is a query over results two leaders
/// independently confirmed — the one number in the app nobody can
/// type — so it takes the numeral tier, and Home's self-reported run count
/// deliberately never does. "0–0" before the first confirmed game, as a
/// scoreboard reads before tip-off.
///
/// **No caption beside it (the user's call, 2026-09-22).** "W–L" and "No games
/// yet" used to sit on its baseline. The five dots say the same thing: five
/// grey dots next to "0–0" is a season that hasn't started. VoiceOver still
/// gets the sentence (`spokenRecord`).
///
/// **The dots are pinned to the band's bottom-right corner** (the user's call,
/// 2026-09-22): the numeral holds the left edge, the dots the right, and their
/// bottoms sit on the numeral's baseline, so the row closes the band on one
/// line. They stay in that corner in either layout.
///
/// Beside the numeral when they fit, beneath it when they don't. With the
/// "L5" label the row is 141pt at the default size (`FormDotMetrics`), and fits
/// beside any record there and beside a single-digit one at every size. A
/// double-digit record at `.accessibility3` moves it beneath the numeral, still
/// on the right — the label cost that fit, and stacking is the fallback doing
/// its job. `FormGuideTests` measures both, and the larger *Differentiate
/// Without Color* dots.
///
/// Shared by squad home and squad detail, for the reason `SquadIdentity` is.
struct SquadRecordLine: View {
    let record: SeasonGame.Record
    let form: [SeasonGame.Outcome]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                numeral
                Spacer(minLength: Spacing.lg)
                dots
            }

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                numeral
                    .frame(maxWidth: .infinity, alignment: .leading)
                dots
            }
        }
    }

    /// The record with its dash set as a separator rather than a third glyph
    /// at numeral weight.
    ///
    /// **A 44pt bold en dash is as heavy as the digits and sits tight against
    /// them**, so "1–0" read as one lump. The dash here is 60% size, semibold,
    /// in secondary text, with a thin space either side at numeral size — the
    /// digits carry the number, the dash only divides it. A smaller dash also
    /// sits lower (a dash's height is a fraction of its own size), so it is
    /// lifted by `dashLift` to the digits' middle again.
    ///
    /// One `Text`, not an `HStack`, so the numeral keeps a single baseline for
    /// the dots to sit on and a single content transition. The digits and
    /// spaces take `hooprType(.numeral)` from outside; only the dash carries a
    /// font of its own, sized off the same scaled value so it grows with
    /// Dynamic Type.
    private var numeralText: Text {
        let size = HooprFontMetrics.scaledSize(
            HooprTextRole.numeral.size,
            at: HooprFontMetrics.contentSizeCategory(for: dynamicTypeSize)
        )
        let dash = Text(RecordDash.glyph)
            .font(.system(size: size * RecordDash.scale, weight: RecordDash.weight))
            .foregroundStyle(Color.hooprSecondaryText)
            .baselineOffset(size * RecordDash.lift)
        let space = RecordDash.space
        return Text("\(record.wins)\(space)\(dash)\(space)\(record.losses)")
    }

    /// Measured, not guessed: SF's en dash centres at about 0.29 of its point
    /// size, so a dash at 0.6× sits 0.4 × 0.29 ≈ 0.115 of the numeral's size
    /// too low. Checked against rendered glyph bounds at 44pt and at the
    /// `.accessibility3` size (65.3pt). Internal so `FormGuideTests` can
    /// measure the numeral as drawn.
    nonisolated enum RecordDash {
        static let glyph = "–"
        static let scale: CGFloat = 0.6
        static let weight = Font.Weight.semibold
        static let uiFontWeight = UIFont.Weight.semibold
        static let lift: CGFloat = 0.115
        /// Either side of the dash, at numeral size.
        static let space = "\u{2009}"
    }

    private var numeral: some View {
        numeralText
            .hooprType(.numeral)
            .foregroundStyle(Color.hooprPrimaryText)
            .hooprNumericTransition(text: record.displayText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Self.spokenRecord(wins: record.wins, losses: record.losses))
    }

    /// The dots have no baseline of their own. This gives them one at their
    /// bottom edge, so `.lastTextBaseline` sets them on the numeral's.
    /// A new result recolours the dots in place (UI revamp Phase 3), on
    /// `hooprSwap`, when `form` changes — which is only when a result is
    /// confirmed, never on the band first drawing.
    private var dots: some View {
        FormGuide(form: form)
            .animation(.hooprSwap, value: form)
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
    }

    /// "1 win, 0 losses this season" — a screen reader gets the sentence a
    /// sighted reader gets from the numeral and the dots. `nonisolated static`
    /// so it's testable without a view.
    nonisolated static func spokenRecord(wins: Int, losses: Int) -> String {
        guard wins + losses > 0 else { return "No games played yet this season" }
        let w = wins == 1 ? "1 win" : "\(wins) wins"
        let l = losses == 1 ? "1 loss" : "\(losses) losses"
        return "\(w), \(l) this season"
    }
}
