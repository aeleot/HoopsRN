# Hoopr — Data Model

**Scope:** `hoopr/Models/`, `hoopr/Support/Distance.swift`
**Verified:** 2026-08-13 @ map-tab

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
check-ins that will reference it. (The abandoned `courts_updated.json` used
`"lat,lon"` strings as IDs; that's the mistake this avoids.)

`osmType` / `osmId` are retained provenance so a future extract can match
existing records instead of minting duplicates.

`Access` (`public` / `school` / `restricted`) is **derived at build time from
the court's name**, not read from an OSM tag: OSM rarely tags apartment- and
hotel-attached courts as private, so the tag alone would classify them as
playable. Current distribution: 171 public, 32 school, 10 restricted.

`hoops`, `surface`, `isLit`, `isCovered` are optional because OSM tags them
inconsistently — most rows are `null`. **None of the five attribute fields
(`access` included) is read anywhere in the app yet**; they decode and sit
unused. See `GAPS.md`.

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

`UserProfile` is Firebase-free by design, like `Court`. Three contracts:

- **`userName` is a display name, not a unique handle.** Nothing — client or
  rules — enforces uniqueness. The rules only bound it to 1–50 characters.
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

`GameError` mirrors `UserProfileError` case-for-case where the meanings match
(`notSignedIn`, `permissionDenied`, `network`, `unknown`), and adds
`invalidSchedule`, `gameNotFound`, and `gameClosed`.

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
- Distances go through `Distance`. Don't reintroduce a local metres-per-mile.

## See also

- `database/DATABASE_SCHEMA.md` — the stored shape and the server-side
  mutability contract.
- `COURT_DATASET.md` — where `Court` values come from and how to regenerate
  them.
- `ARCHITECTURE.md` — the vendor boundary these types exist to hold.
