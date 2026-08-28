import Foundation

/// Local court search, shared by every surface that looks a court up by name.
///
/// No geocoder and no network. The dataset is 214 rows already resident in
/// memory and offline-first is a product guarantee, so a substring scan beats a
/// round trip on both latency and availability. It also means no debounce is
/// warranted at the call sites: unlike a Firestore-backed people search, a
/// keystroke here costs a pass over an array.
enum CourtSearch {
    /// Enough to scroll through without rendering the whole dataset for a
    /// one-letter query.
    static let defaultLimit = 25

    /// Courts matching `query`, name matches ahead of city matches.
    ///
    /// **Both name fields are searched, not one.** `Court.displayName` strips
    /// the dataset's "Basketball Court" boilerplate, so the stored and
    /// displayed spellings catch different queries: "Park #2" matches the
    /// stripped `"Long Meadow Park #2"` and misses the stored
    /// `"Long Meadow Park Basketball Court #2"`, while "basketball" does the
    /// reverse. Searching either field alone silently drops real hits.
    ///
    /// Name matches rank above city matches so typing a court's name doesn't
    /// bury it under every other court in the same town.
    ///
    /// - Returns: at most `limit` courts, in the order described above. Empty
    ///   for a blank or whitespace-only query — a caller showing suggestions
    ///   wants nothing rather than everything before the user has typed.
    static func matches(
        _ courts: [Court],
        query: String,
        limit: Int = defaultLimit
    ) -> [Court] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        // One pass, partitioned as it goes, rather than two `filter`s over the
        // whole dataset — and it keeps a court that matches on both a name and
        // its city from landing in the result twice.
        var nameMatches: [Court] = []
        var cityMatches: [Court] = []

        for court in courts {
            if court.matchesAnyName(trimmed) {
                nameMatches.append(court)
            } else if court.city.localizedCaseInsensitiveContains(trimmed) {
                cityMatches.append(court)
            }
        }

        return Array((nameMatches + cityMatches).prefix(limit))
    }
}

private extension Court {
    /// The stored name or the stripped one — see `CourtSearch.matches`.
    func matchesAnyName(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || displayName.localizedCaseInsensitiveContains(query)
    }
}
