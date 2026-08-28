# hoopsRN — Data Model

**Scope:** `hoopr/Models/`, `hoopr/Support/Distance.swift`,
`hoopr/Support/InviteLink.swift`, `hoopr/Support/CourtSearch.swift`
**Verified:** 2026-08-27 @ 37aaf7a

The domain types and the contracts attached to them. Read this before
changing a field, adding one, or deciding how something gets persisted. The
field lists themselves are plain on reading the files — what's here is the
reasoning that isn't.

---

## `Court`

`id` is a **stable UUID minted at dataset build time, deliberately not derived
from coordinates.** The build scripts compute it as `uuid5` over the OSM
type/id, so re-extracting later yields the same ID for the same real-world
court — and correcting a court's position never orphans the games, ratings, or
check-ins that will reference it. (The abandoned `courts_updated.json`, since
deleted, used `"lat,lon"` strings as IDs; that's the mistake this avoids.)

`osmType` / `osmId` are retained provenance so a future extract can match
existing records instead of minting duplicates.

`Access` (`public` / `school` / `restricted`) is **derived at build time from
the court's name**, not read from an OSM tag: OSM rarely tags apartment- and
hotel-attached courts as private, so the tag alone would classify them as
playable. Current distribution: 172 public, 32 school, 10 restricted.

`hoops`, `surface`, `isLit`, `isCovered` are optional because OSM tags them
inconsistently — most rows are `null`. `CourtBadges` renders all five on the
list row and the map's detail card. Absent means unknown, so nothing is inferred
and no placeholder badge is shown.

**`CourtFilter` no longer reads any of them except `access`.** It filtered on
`isLit` and `hoops` until 2026-08-27, and that sparsity made the filters
destructive rather than merely weak: `isLit` is `null` for 193 of 214 courts and
an absent tag is excluded, so one tap hid 95% of the map. The chips are now
activity predicates — "Games today", "Open spots", and "Open to all" (`access`,
the one attribute field the dataset populates well at 172/214). They take a
`CourtActivity`, because whether anyone is playing is a join between bundled
geography and Firestore that `Court` cannot answer alone.

`CourtActivity` is that joined half: today's runs at one court, with `.quiet`
for a court with nothing on. Having a total value rather than an optional is
what keeps every filter predicate total — the absent-tag third state that made
the amenity filters dangerous has no equivalent here.

`displayName` is `name` with the words "basketball court" stripped and the
leftover whitespace collapsed. **Every one of the 214 courts in the dataset is
named `<Place> Basketball Court`**, so the words carry no information in an app
where everything is a basketball court — they only push real names onto a second
and third line. It falls back to the stored `name` when stripping would leave
nothing (a court named only after its type). This is derivation, not storage:
`name` is what the dataset holds and what a regeneration overwrites.
`CourtTests` pins the rule, because a string substitution is exactly what
quietly starts mangling names when the dataset's naming changes.

## `CourtDataset`

The versioned envelope around the bundled file: `version`, `generated`,
`attribution`, `cities`, `courts`. `version` exists so a future CDN-hosted copy
can be compared against the bundled one without parsing the court array.
`CourtService` reads `version` and `attribution` into stored properties;
neither is displayed anywhere yet, and the ODbL attribution string in
particular is a licence obligation currently unmet in the UI.

---

## `AuthenticatedUser` and `AuthError`

`AuthenticatedUser` is just `id` + `email?` — the app's own stand-in so no
`FirebaseAuth.User` escapes `AuthService`.

`AuthError` cases and what each actually means:

| Case | Means |
|---|---|
| `invalidEmail`, `emailAlreadyInUse`, `weakPassword` | The obvious form-level failures. `weakPassword` is Firebase's 6-character minimum. |
| `wrongCredentials` | Maps **both** `.wrongPassword` and `.invalidCredential` — modern Firebase projects with email enumeration protection return the latter for a bad password. |
| `userNotFound`, `userDisabled` | Account-level. With enumeration protection on, `userNotFound` rarely appears. |
| `network`, `tooManyRequests` | Transport and throttling. |
| `notConfigured` | **Authentication was never enabled on the Firebase project at all.** The SDK has no error code for this — it arrives as a generic internal error whose `userInfo` contains `CONFIGURATION_NOT_FOUND`, which is why `mapped(_:)` string-matches for it *before* looking at `AuthErrorCode`. |
| `providerDisabled` | Maps `.operationNotAllowed` — the project exists but email/password sign-in is switched off. |
| `unknown(String)` | Carries `localizedDescription`; `LoginViewModel` shows it verbatim. |

## `UserProfile` and `UserProfileError`

`UserProfile` is Firebase-free by design, like `Court`. Five contracts:

- **Every field here is visible to every other player.** The `users` read rule
  grants any signed-in user and Firestore has no field-level read ACLs, so a
  document is readable whole or not at all. That's why the model has **no
  `email`**: it was stored, read by nothing (the profile screen takes the
  address from `AuthService`), and handed every account's address to every
  other account. Private data belongs in an owner-only subcollection instead.
- **`userName` is a display name, not a unique handle.** Nothing — client or
  rules — enforces uniqueness. The rules only bound it to 1–50 characters.
- **`userNameLower` is derived, never edited.** It's the lowercased mirror
  player search prefix-matches on, produced by `UserProfile.searchKey(_:)` and
  written in the same field map as `userName` — the two must never move
  separately, or a profile becomes findable under a name it doesn't display.
  Optional, because profiles provisioned before search existed don't have one.
- **`id` duplicates the Firestore document ID** so the model decodes without
  optionals for the one field everything keys on.
- **`preferredRadius` controls the nearby courts search range** (1–50 miles,
  default 5). The map tab filters its court list to this radius.

**Never read `preferredRadius` directly — go through `effectivePreferredRadius`
or `validRadius(_:)`.** The field is optional *and* unvalidated for rows that
already exist: `firestore.rules` bounds what a client may write, but nothing
sweeps documents that were seeded by hand in the console. A `0` there is a
perfectly good `Double`, so a plain `?? 5` accepts it and the nearby list
silently empties — every court is further than zero miles away. `validRadius`
treats out-of-range exactly like absent. This is the same class of bug as a
stale `homeCourtId`, and it fails far more quietly.

**Never hand this struct to `setData(from:)`.** `UserProfileService` writes
explicit `[String: Any]` field maps so that server timestamps stay
server-assigned and `createdAt` is never clobbered by a later update. Encoding
the whole struct would send a client-side `createdAt` and be rejected by the
rules anyway.

`createdAt` / `updatedAt` are optional `Date?` because a document read back
before the server resolves a `serverTimestamp()` sentinel carries nulls —
covered by `testDecodesPendingServerTimestamps`.

`UserProfileError`:

| Case | Means |
|---|---|
| `notSignedIn` | No `observedUID` — a write was attempted with no session. |
| `emptyUserName` | Client-side guard before the write; the rules reject it too. |
| `permissionDenied` | Firestore `permission-denied`. **Almost always undeployed rules**, or rules deployed to the wrong project — not a genuine authorization bug. |
| `network` | Maps both `unavailable` and `deadlineExceeded`. |
| `decodingFailed(String)` | The stored document drifted from the model (a renamed field). |
| `unknown(String)` | Anything outside `FirestoreErrorDomain`, or an unmapped code. |

---

## `Game` and `GameError`

The first type describing state more than one person writes. Firebase-free like
the rest; `GameService` owns all encoding.

- **`id` mirrors a Firestore-generated document ID**, not a natural key — a
  person hosts many runs, so there's nothing to key on. It's a stored field
  purely so the model decodes without `@DocumentID`, which is a Firebase
  property wrapper and would move the vendor boundary into `Models/`.
- **`scheduledTime` is non-optional; `createdAt`/`updatedAt` are not.** The
  first is client-supplied and can never read back as an unresolved sentinel;
  the other two are `serverTimestamp()` and can.
- **`status` is derived, never chosen.** `Game.status(playerCount:maxPlayers:)`
  is the client's copy of an expression `firestore.rules` also evaluates. They
  must stay identical — a divergence turns every write into a
  `permission-denied`, which reads like an undeployed ruleset rather than a
  logic bug. `inProgress` carries the raw value `in_progress`; nothing writes
  it yet.
- **`queuedPlayerIds` is non-optional and always stored**, `[]` when empty. The
  one deliberate exception to the "absent, never null" convention, because the
  update rule diffs both rosters together.
- **`isVisible(at:)` is what actually retires a run.** The Firestore query's
  cutoff is fixed when its listener attaches, so a session left open for hours
  would keep showing a run that has since aged out. Re-applying the predicate on
  every rebuild is the fix — and keeping it a pure function on the model is what
  makes it testable without Firestore.

- **`inviteLink` is derived from the ID and exists on every run**, public or
  not — whether it's worth showing is a visibility question the views answer.
  The format itself lives in `Support/InviteLink.swift` rather than on the
  model, because the create sheet builds one from a bare document ID before any
  `Game` exists. `GameTests` pins the exact string; see below.

`GameError` mirrors `UserProfileError` case-for-case where the meanings match
(`notSignedIn`, `permissionDenied`, `network`, `unknown`), and adds
`invalidSchedule`, `gameNotFound`, and `gameClosed`.

## `Friendship` and `FriendError`

One document per pair of people, at `friendships/{uidA}_{uidB}`. Firebase-free
like the rest; `FriendService` owns all encoding.

- **`id` is computed, not stored** — `"\(uidA)_\(uidB)"`. This is the deliberate
  opposite of `Game.id`, and the difference is where the ID comes from: a game's
  is generated by Firestore and has to be mirrored to be seen, while a
  friendship's is *derived* from two fields the document already carries. The
  create rule recomputes it and rejects any mismatch, and its key allowlist has
  no `id` in it, so a stored copy couldn't be written even if it were wanted.
- **`Status` has exactly two cases**, `pending` and `accepted`. Declining,
  cancelling and unfriending delete the document rather than adding a third —
  the same "absence, never a tombstone" call that leaves `Game.Status` without
  a `cancelled`.
- **`Direction` is computed from `requestedBy`, never stored.** `direction(for:)`
  answers "sent, received, or mutual" from the caller's point of view. Storing
  "sent" on one person's copy and "received" on the other's is exactly the
  two-copies-that-can-drift shape the single-document schema exists to avoid.
- **`id(for:_:)` is order-independent**, so both participants compute the same
  document ID from the same pair. Firebase uids are ASCII alphanumeric, which is
  what lets Swift's `<` and the rules language's `<` agree on the ordering.
- **`createdAt`/`updatedAt` are optional** for the usual reason — they're
  `serverTimestamp()` sentinels and read back null until the server resolves
  them. Here that's the *common* case rather than a corner one: the person who
  just sent a request sees their own write before it's stamped, which is why
  `FriendService` sorts an unresolved timestamp to the top rather than the
  bottom.

`FriendError` mirrors `GameError` case-for-case where the meanings match
(`notSignedIn`, `permissionDenied`, `indexRequired`, `network`, `unknown`), and
adds `cannotFriendSelf` and `requestNotFound`.

## `InviteLink`

One definition of `hoopsrn://game/{id}`, the URL a host sends to reach an
invite-only run. Two call sites need it from different starting points — the
create sheet has the document ID `GameService.createGame` returns, the queued
card has a whole `Game` — so the format is a static function with a thin
`Game.inviteLink` convenience over it.

The ID is percent-encoded against unreserved characters only, narrower than
`.urlPathAllowed`, which leaves `/` alone and would let a hand-written ID split
into two path components. Firestore's own IDs are alphanumeric, so this never
fires in practice.

**Only the sending half exists.** `hoopsrn://` is not a registered URL scheme,
nothing implements `.onOpenURL`, and the `games` read rule still refuses a
non-member — so a recipient tapping the link today gets nothing. `GAPS.md` §4
holds the design for the rest, which is a real authorization decision rather
than more UI.

## `Distance`

Miles conversion and the `"1.2 mi"` / `"12 mi"` format rule, in one place.
Extracted because the nearby-courts list and the Local Runs list measure from
the same origin and render the same string — before this each carried its own
copy of the conversion factor.

---

## Invariants

- `Court.id` is never derived from coordinates. If the dataset is rebuilt, IDs
  must stay stable for the same OSM feature — that's what `uuid5(NAMESPACE,
  osmType/osmId)` in the build scripts guarantees.
- `UserProfile` never goes through `setData(from:)` or `Codable` encoding on
  the write path. Writes are explicit field maps in `UserProfileService`.
- Models import no Firebase module. Adding one moves the vendor boundary.
- `createdAt` is write-once. Nothing may include it in an update payload.
- `preferredRadius` is read through `effectivePreferredRadius` / `validRadius`,
  never directly. Stored rows are not guaranteed to be in range.
- `Game.status` is derived on both sides of the wire. Changing the client
  helper without the matching rules expression breaks every write.
- A `Friendship`'s direction and document ID are computed from stored fields,
  never stored themselves. Adding either as a field would create a second copy
  that can disagree with the first.
- Distances go through `Distance`. Don't reintroduce a local metres-per-mile.
- Anything user-facing names a court through `Court.displayName`, not `name`.
  Six screens do; a seventh reaching for `name` reintroduces the wrapped
  three-line labels the derivation exists to remove.

## See also

- `database/DATABASE_SCHEMA.md` — the stored shape and the server-side
  mutability contract.
- `COURT_DATASET.md` — where `Court` values come from and how to regenerate
  them.
- `ARCHITECTURE.md` — the vendor boundary these types exist to hold.
