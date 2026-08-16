import Foundation

/// The one definition of a run's invite URL.
///
/// Lives in `Support/` rather than on `Game` because the create flow holds a
/// fresh document ID and no model yet, while the queued card holds a whole
/// run — both need the same string, and a second copy of `"hoopsrn://game/"`
/// spelled slightly differently is exactly the kind of drift that only shows
/// up once a recipient taps a link that goes nowhere.
///
/// **The link is not yet openable.** Nothing registers `hoopsrn://` and nothing
/// handles an incoming URL, so today this is a string a host can send while
/// the receiving half is built — see `GAPS.md` §4.
enum InviteLink {
    /// Must match the `CFBundleURLSchemes` entry once the scheme is registered.
    static let scheme = "hoopsrn"

    /// The path component the deep-link handler will key on.
    static let gameHost = "game"

    /// Unreserved characters only — narrower than `.urlPathAllowed`, which
    /// leaves `/` alone and would let an ID split into two path components.
    private static let idAllowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))

    /// e.g. `hoopsrn://game/abc123`.
    ///
    /// Firestore's generated IDs are alphanumeric, so the encoding never fires
    /// in practice — it's there so a hand-written ID can't produce a string
    /// that isn't a URL, or one that parses back as a different ID.
    static func text(forGameId gameId: String) -> String {
        let encoded = gameId.addingPercentEncoding(
            withAllowedCharacters: idAllowed
        ) ?? gameId
        return "\(scheme)://\(gameHost)/\(encoded)"
    }
}

extension Game {
    /// The invite link for this run. Present on every run — whether it's worth
    /// showing is a visibility question the views answer, not the model.
    var inviteLink: String {
        InviteLink.text(forGameId: id)
    }
}
