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
/// Beside the numeral when they fit, beneath it when they don't. The dots are
/// 112pt (`FormDotMetrics`), which fits beside even a "10–10" at
/// `.accessibility3`. With *Differentiate Without Color* on they are 142pt,
/// and a double-digit record at that size moves them beneath the numeral,
/// still on the right. `FormGuideTests` measures both.
///
/// Shared by squad home and squad detail, for the reason `SquadIdentity` is.
struct SquadRecordLine: View {
    let record: SeasonGame.Record
    let form: [SeasonGame.Outcome]

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

    private var numeral: some View {
        Text(record.displayText)
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
