import Foundation

/// The one definition of a run's invite URL — minted here, and parsed back
/// here.
///
/// Lives in `Support/` rather than on `Game` because the create flow holds a
/// fresh document ID and no model yet, while the queued card holds a whole
/// run — both need the same string, and a second copy of `"hoopsrn://game/"`
/// spelled slightly differently is exactly the kind of drift that only shows
/// up once a recipient taps a link that goes nowhere. The parser sits beside
/// the minter for the same reason: `GameTests` round-trips one through the
/// other, so the two halves can't disagree.
///
/// **The link opens the run** (2026-10-08). `hoopsrn` is registered under
/// `CFBundleURLSchemes` in `hoopr/Info.plist`; `hooprApp` hands an incoming URL
/// to `InviteRouter`, and the shell presents `InviteJoinSheet` for it. A
/// recipient who isn't on the run can read it because the `games` read rule is
/// split into `get` (any signed-in account, by ID) and `list` (unchanged) —
/// see `context/database/DATABASE_SCHEMA.md`.
nonisolated enum InviteLink {
    /// Must match the `CFBundleURLSchemes` entry in `hoopr/Info.plist`.
    static let scheme = "hoopsrn"

    /// The URL host the handler keys on — `hoopsrn://game/…`.
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

    /// The run a URL names, or `nil` when it isn't an invite this app can open.
    ///
    /// **This is input from outside the app**, so it is checked, not trusted:
    /// a link can be hand-edited, truncated by a messaging app, or simply
    /// another scheme's URL. The result is handed to
    /// `Firestore.document(_:)`, which *traps* on an ID containing `/` (it
    /// becomes a collection path) or on an empty one, so a malformed link has
    /// to stop here rather than crash the app it was sent to.
    ///
    /// Forgiving about what's harmless: the scheme and host in any case, and
    /// one trailing slash. Strict about the rest: exactly one path component.
    static func gameId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == gameHost
        else { return nil }

        // The *encoded* path, split before decoding — so a `%2F` inside an ID
        // stays inside it and is then refused below, rather than decoding into
        // a separator and quietly naming some other document.
        var path = components.percentEncodedPath
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix("/") { path.removeLast() }

        guard !path.contains("/"),
              let gameId = path.removingPercentEncoding,
              isWellFormed(gameId: gameId)
        else { return nil }

        return gameId
    }

    /// Whether Firestore would accept `gameId` as a document ID in `games`.
    ///
    /// Firestore's own constraints, not a guess at what its generator emits:
    /// non-empty, no `/`, not `.` or `..`, not the reserved `__name__` form,
    /// at most 1,500 bytes. `GameService.fetchGame(id:)` checks it too, so the
    /// trap it guards can't be reached from a call site that skipped the parser.
    static func isWellFormed(gameId: String) -> Bool {
        !gameId.isEmpty
            && !gameId.contains("/")
            && gameId != "."
            && gameId != ".."
            && !(gameId.hasPrefix("__") && gameId.hasSuffix("__"))
            && gameId.utf8.count <= 1_500
    }
}

extension Game {
    /// The invite link for this run. Present on every run — whether it's worth
    /// showing is a visibility question the views answer, not the model.
    var inviteLink: String {
        InviteLink.text(forGameId: id)
    }
}
