# Hoopr — Data Model

**Scope:** `hoopr/Models/`
**Verified:** 2026-08-07 @ 2d483bb

The four domain types and the contracts attached to them. Read this before
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

`UserProfile` is Firebase-free by design, like `Court`. Two contracts:

- **`userName` is a display name, not a unique handle.** Nothing — client or
  rules — enforces uniqueness. The rules only bound it to 1–50 characters.
- **`id` duplicates the Firestore document ID** so the model decodes without
  optionals for the one field everything keys on.

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

## Invariants

- `Court.id` is never derived from coordinates. If the dataset is rebuilt, IDs
  must stay stable for the same OSM feature — that's what `uuid5(NAMESPACE,
  osmType/osmId)` in the build scripts guarantees.
- `UserProfile` never goes through `setData(from:)` or `Codable` encoding on
  the write path. Writes are explicit field maps in `UserProfileService`.
- Models import no Firebase module. Adding one moves the vendor boundary.
- `createdAt` is write-once. Nothing may include it in an update payload.

## See also

- `database/DATABASE_SCHEMA.md` — the stored shape and the server-side
  mutability contract.
- `COURT_DATASET.md` — where `Court` values come from and how to regenerate
  them.
- `ARCHITECTURE.md` — the vendor boundary these types exist to hold.
