import Foundation

/// Refuses display names and squad names that contain an objectionable word
/// (App Review Guideline 1.2's "method for filtering objectionable material").
///
/// Both names are typed by one person and shown to strangers — in player
/// search, on squad crests, on an opponent's match card — and until this
/// existed they were checked for length and nothing else.
///
/// **Whole words, not substrings.** A substring match refuses "Scunthorpe",
/// "Dickson" and "Cockburn", and a filter that rejects real names gets turned
/// off. So a name is split into words and each word is compared against the
/// list; a word that merely *contains* a listed term passes.
///
/// Three things are folded away before comparing, because they are the
/// evasions that cost nothing to type: case, accents, and the usual
/// digit-for-letter swaps (`sh1t`, `a55`). The whole name with its separators
/// removed is also checked, which catches a term spelled out with dots or
/// spaces between the letters. Anything more determined than that gets
/// through, and is what the Report action is for — this is the cheap first
/// line, not the moderation.
///
/// **Client-side only.** Rules can't hold a word list, so a modified client
/// can still store any name it likes; the report path and the console are the
/// answer to that, the same ceiling `context/gaps/RATE_LIMITING.md` describes.
nonisolated struct NameFilter: Sendable {
    /// Lowercased, already folded.
    let terms: Set<String>

    init(terms: some Sequence<String>) {
        self.terms = Set(terms.map(Self.folded).filter { !$0.isEmpty })
    }

    /// The list shipped in the app bundle, `Resources/blocked_terms.txt`.
    ///
    /// Empty if the file is missing, which lets every name through rather than
    /// refusing every name — `NameFilterTests` fails on an empty list so that
    /// can't happen quietly.
    static let bundled: NameFilter = {
        guard
            let url = Bundle.main.url(forResource: "blocked_terms", withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return NameFilter(terms: [])
        }
        return NameFilter(terms: parse(contents))
    }()

    /// One term per line; `#` starts a comment, blank lines are skipped.
    static func parse(_ contents: String) -> [String] {
        contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Whether `name` is free of every listed term.
    func isAllowed(_ name: String) -> Bool {
        guard !terms.isEmpty else { return true }

        let words = Self.words(in: name)
        if words.contains(where: terms.contains) { return false }

        // "f.u.c.k", "s h i t": single letters with separators between them.
        // Only runs of one-letter words are joined, so two ordinary words that
        // happen to concatenate into a term ("Grape Stars") are left alone.
        return !Self.spelledOutWords(from: words).contains(where: terms.contains)
    }

    // MARK: - Folding

    /// The comparable words in `text`: split on anything that isn't a letter
    /// or digit, then folded.
    static func words(in text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { folded(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Lowercased, accents stripped, and the common digit swaps undone.
    static func folded(_ word: String) -> String {
        let plain = word
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        return String(plain.map { digitSwaps[$0] ?? $0 })
    }

    private static let digitSwaps: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
    ]

    /// Each maximal run of two or more one-character words, joined.
    static func spelledOutWords(from words: [String]) -> [String] {
        var joined: [String] = []
        var run = ""

        func flush() {
            if run.count > 1 { joined.append(run) }
            run = ""
        }

        for word in words {
            if word.count == 1 {
                run += word
            } else {
                flush()
            }
        }
        flush()
        return joined
    }
}
