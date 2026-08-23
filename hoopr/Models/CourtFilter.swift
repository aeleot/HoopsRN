import Foundation

/// The chips shown above the map. Each one narrows both the pins and the list.
///
/// Every case reads a field that already ships in `courts.json`, so filtering
/// costs nothing at runtime and needs no network.
/// There is deliberately no "Covered" chip: `isCovered` is true for zero courts
/// in the current dataset, so the filter would only ever empty the list. Add it
/// back when the data supports it.
enum CourtFilter: String, CaseIterable, Identifiable, Sendable {
    case lit
    case multipleHoops
    case publicOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lit:           "Lit"
        case .multipleHoops: "2+ hoops"
        case .publicOnly:    "Public"
        }
    }

    var symbolName: String {
        switch self {
        case .lit:           "lightbulb"
        case .multipleHoops: "basketball"
        case .publicOnly:    "figure.walk"
        }
    }

    /// OSM tags these fields come from are sparsely populated, so an absent
    /// value means "unknown", never "no". Filters therefore exclude anything
    /// we can't positively confirm.
    func matches(_ court: Court) -> Bool {
        switch self {
        case .lit:
            return court.isLit == true
        case .multipleHoops:
            return (court.hoops ?? 0) >= 2
        case .publicOnly:
            return court.access == .public
        }
    }
}
