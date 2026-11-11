import SwiftUI

/// A court's name on one line, shortened to fit rather than wrapped.
///
/// **The map's rule, at the user's direction (2026-09-22):** a name that doesn't
/// fit sheds the word "Park", then its court number, and only then is cut with
/// an ellipsis. The map is a place you scan — the court card, the Nearby and Now
/// rows, search results — and a name that wraps to two or three lines there
/// costs the rows their shared height and the card its compact header. The
/// full name, "Park" and number included, is always one tap away and is what
/// the Runs tab shows.
///
/// **Why "Park" goes first.** It is the least informative word in the name —
/// generic, like the "Basketball Court" that `Court.displayName` already strips
/// — while the court number is the only thing telling sibling courts apart:
/// "Long Meadow Park #1" and "#3" are different courts. So "Long Meadow Park #3"
/// becomes "Long Meadow #3" before it becomes "Long Meadow".
///
/// **Only a trailing "Park" is dropped.** Four names in the dataset carry it
/// mid-name — "Lake Park Trail", "Ting Park Soccer Field A" — where it is part
/// of the place, not a descriptor, and removing it would name somewhere else.
///
/// Font and colour come from the call site: they are environment values, so a
/// `.hooprType` or `.foregroundStyle` applied to this reaches every form.
struct CourtName: View {
    let name: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.forms(of: name), id: \.self) { form in
                Text(form)
                    .lineLimit(1)
            }

            // Nothing fits whole: the shortest form, cut at the end.
            Text(Self.forms(of: name).last ?? name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // Whatever form is on screen, VoiceOver reads the real name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    /// Every form `name` can take, longest first, without repeats — the full
    /// name, then without a trailing "Park", then without its court number.
    nonisolated static func forms(of name: String) -> [String] {
        var forms = [name]

        let withoutPark = droppingTrailingPark(from: name)
        if withoutPark != forms.last { forms.append(withoutPark) }

        let withoutNumber = droppingCourtNumber(from: withoutPark)
        if withoutNumber != forms.last { forms.append(withoutNumber) }

        return forms
    }

    /// "East End Park" → "East End"; "Long Meadow Park #3" → "Long Meadow #3".
    /// A name that *is* "Park", or has it anywhere but last, is returned as is.
    nonisolated static func droppingTrailingPark(from name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        let number = words.last.map(isCourtNumber) == true ? words.removeLast() : nil

        guard words.count > 1, words.last?.lowercased() == "park" else { return name }
        words.removeLast()
        if let number { words.append(number) }
        return words.joined(separator: " ")
    }

    /// "Apex #10" → "Apex". The dataset's only numbering shape is `#N`.
    nonisolated static func droppingCourtNumber(from name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last, isCourtNumber(last) else { return name }
        words.removeLast()
        return words.joined(separator: " ")
    }

    private nonisolated static func isCourtNumber(_ word: String) -> Bool {
        word.hasPrefix("#") && word.count > 1 && word.dropFirst().allSatisfy(\.isNumber)
    }
}
