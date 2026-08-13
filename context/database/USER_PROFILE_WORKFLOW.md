# Hoopr — User Profile Workflow

**Scope:** runtime auth + profile behaviour (`AuthService`, `UserProfileService`,
`ProfileViewModel`, `Views/Profile/`)
**Verified:** 2026-08-07 @ 2d483bb

How the app connects to Firestore and what happens at runtime between someone
signing in and a rendered profile. This is the first Hoopr feature backed by a
real database, so it also establishes the patterns every later collection
(matches, queues) should follow.

---

## 1. Why there's a profile at all

Firebase Auth already knows *who you are* — it issues a uid and holds your
email. It does **not** hold anything other players should see.

Two separate layers, deliberately:

| | Firebase Auth | Firestore `users/{uid}` |
|---|---|---|
| Owns | Identity + credentials | App-owned profile data |
| Provides | `uid`, `email` | `userName`, `homeCourtId`, future profile fields |
| Who can read it | Only the account itself | Any signed-in user |
| Managed by | `AuthService` | `UserProfileService` |

Before this, the greeting guessed a name by slicing the email at the `@`. That
guess was recomputed on every render, was never stored, and could never be
corrected by the user. The profile document replaces it with a real stored
value — and the same heuristic now runs *once*, at provisioning time, as the
seed name.

---

## 2. Identity: where the ID comes from

**The app does not generate user IDs.** Firebase Auth mints a uid when the
account is created. That uid is used in two places:

```
users/Usc2MRkQN5dfFD9YYOTybOrkyuP2      ← document ID
  └─ id: "Usc2MRkQN5dfFD9YYOTybOrkyuP2" ← duplicated as a field
```

Why reuse the Auth uid instead of a fresh key:

- **Direct addressing** — `users/{uid}` needs no query to resolve a profile.
- **Simpler rules** — `request.auth.uid == uid` compares against the document
  path itself.
- **Stability** — the uid never changes for the life of the account and is never
  reused. Changing your email does not change it.

The `id` field duplicates the document ID so the Swift model decodes without
optionals, matching how `Court` is modeled.

---

## 3. Schema

Defined in `DATABASE_SCHEMA.md`. In short: `id` (Auth uid, immutable),
`userName` (1–50 chars, editable, not unique), `email` (denormalized from Auth,
display only), `homeCourtId` (a `Court.id`, editable, deleted when cleared),
`preferredRadius` (1–50 miles, editable, defaults to 5), `createdAt` (write-once)
and `updatedAt` (refreshed on every write).

`userName`, `homeCourtId`, and `preferredRadius` are the only fields a client
can ever change. Enforced server-side, not by convention.

The 1–50 character bound on `userName` is enforced client-side too, by
`UserProfile.validate(userName:)` — the sheet's Save button and
`updateUserName` both call it. Without that, a 51-character name comes back as
`permission-denied` and reads like a deployment problem.
`FirestoreRulesParityTests` keeps the two copies of `50` together.

---

## 4. How the connection is set up

**a. SDK** — `FirebaseFirestore` is linked via SPM (`firebase-ios-sdk` 12.16.0),
alongside `FirebaseAuth` and `FirebaseCore`.

**b. Initialization** — `FirebaseApp.configure()` runs at the very top of
`hooprApp.init()`, **before any service is constructed**.

> This ordering is load-bearing. `AuthService.init()` calls `Auth.auth()`, which
> traps if Firebase isn't configured yet. Services are built eagerly in `init()`
> (because `UserProfileService` needs `AuthService` injected, and `@StateObject`
> defers property initializers via `@autoclosure`), so configuration cannot be
> left to the app delegate's later `didFinishLaunching` callback. The
> `AppDelegate` is retained only as a hook for future APNs registration and must
> **not** configure Firebase a second time.

`UserProfileService.database` is additionally `lazy`, so the Firestore singleton
is never touched before configuration either.

**c. Project config** (repo root, version controlled):

```
.firebaserc              → project hoopsrn-4f1e9
firebase.json            → points at the rules + indexes files
firestore.rules          → security rules (source of truth)
firestore.indexes.json   → composite indexes (empty; none needed yet)
```

**d. Deploying rules** — the repo is authoritative; the console is not. Redeploy
after any rules change:

```bash
firebase deploy --only firestore:rules
```

Until rules are deployed, a new database denies every read and write, and the
app surfaces "Can't load your profile — the server refused the request. The
Firestore security rules are probably not deployed." Deploy them and the
listener re-attaches on its own within a few minutes; no relaunch.

---

## 5. Runtime flow

```
User signs in
  └─ AuthService (FirebaseAuth listener) publishes currentUser
       └─ UserProfileService reacts (it subscribes to AuthService itself)
            ├─ attaches a snapshot listener on users/{uid}
            └─ provisions the document if it doesn't exist
                 └─ write lands → listener fires → currentProfile published
                      ├─ MainTabView greeting shows the stored name
                      └─ ProfileView shows the field list, allows editing
```

### Sign-in, step by step

1. `AuthService` emits an `AuthenticatedUser` (uid + email).
2. `handleAuthChange` checks the **`observedUID` guard** and returns early if the
   uid is unchanged. Firebase re-emits the same user on token refresh; without
   this the listener would be torn down and reattached on every refresh,
   flickering `currentProfile` to nil each time.
3. On a genuinely new uid, `startObserving` records the user, clears
   `currentProfile` and `errorMessage`, and calls `attachListener`, which:
   - removes any previous listener;
   - attaches a real-time listener to `users/{uid}`;
   - kicks off `provisionProfileIfNeeded` in parallel.

   `attachListener` is **also the recovery path** — `ListenerSupervisor` calls
   it after a terminal listener error (see `ARCHITECTURE.md`). Provisioning
   re-runs on a retry deliberately: if the first attempt was refused because the
   ruleset wasn't deployed, re-attaching the listener alone would leave the
   account permanently without a profile document. That's why the service holds
   the whole `AuthenticatedUser` rather than just the uid — the fallback name is
   seeded from the email, which a retry still needs.
4. **Provisioning** reads the document once. If it exists, it does nothing —
   idempotent, so it's safe on every sign-in. If missing, it writes `id`,
   `userName` (seeded from the email local part, `aeleot11@gmail.com` →
   `aeleot11`, or `"Hooper"` if Auth has no email), `email` **only if present**,
   and `createdAt`/`updatedAt` as `FieldValue.serverTimestamp()`.
5. The write triggers the listener, which decodes into `UserProfile` and
   publishes it. The UI updates reactively — no manual refresh.

A snapshot for a document that doesn't exist is **not** treated as an error —
provisioning may still be in flight, so `currentProfile` just stays nil.

Provisioning exists because accounts created *before* this feature shipped have
no profile document. Rather than a one-off migration, every sign-in self-heals.

### The edit cycle

The profile screen shows five fields. Three are editable:

| Field | Source | Editable |
|---|---|---|
| Username | `userName` | yes — text sheet |
| Email | Firebase Auth | no — changing it needs an Auth re-authentication flow |
| Home Court | `homeCourtId` → resolved via `CourtService` | yes — searchable court picker |
| Preferred Radius | `preferredRadius` | yes — slider (1–50 miles) |
| Date Joined | `createdAt` | no — write-once by design |

1. Tapping an edit icon calls `beginEditing(_:)`, which clears any error, seeds
   `nameDraft` from the current value for the username case, and sets
   `editingField` — which the `.sheet(item:)` binding presents.
2. `isSaving` gates the whole cycle: `canSaveName` is false while it's true, the
   picker sheet is `.disabled(isSaving)`, and the toolbar swaps Save for a
   `ProgressView`.
3. Saving calls the matching service method, which writes **only** that field
   plus `updatedAt`. `createdAt` is never in the payload.
4. On success `editingField` is cleared and the sheet dismisses; on failure the
   sheet stays open showing the mapped message.
5. The listener fires with the new value; the greeting and profile screen both
   update, because they read the same published state.

Cancelling clears `editingField`, the draft, and the error — nothing is written.
Clearing a home court writes `FieldValue.delete()`, removing the field rather
than storing an explicit null.

### Sign-out

`handleAuthChange(to: nil)` → `stopObserving`: the listener is removed and
`observedUID`, `currentProfile` and `errorMessage` are all cleared, so no stale
data leaks into the next session.

---

## 6. Code map

| File | Responsibility |
|---|---|
| `Models/UserProfile.swift` | The profile struct. **Free of Firebase types**, like `Court`. Decode-oriented — never hand it to `setData(from:)`. |
| `Services/UserProfileService.swift` | The only file that reads/writes `users`. Owns the listener, provisioning, and updates. Translates Firestore errors into `UserProfileError`. |
| `ViewModels/ProfileViewModel.swift` | Profile screen state: field values, which field is being edited, save/cancel, sign-out. Resolves `homeCourtId` to a court name via `CourtService`. |
| `Views/Profile/ProfileView.swift` | The full-screen profile: orange identity header (3/12 of the screen), field list, sign-out. |
| `Views/Profile/ProfileFieldRow.swift` | One label/value row. `onEdit: nil` renders it read-only. |
| `Views/Profile/ProfileEditSheets.swift` | The username editor and the searchable home-court picker. |
| `Views/MainTabView.swift` | Greeting reads `currentProfile?.userName`; presents `ProfileView` **in place of** the tab interface. |
| `hooprApp.swift` | `FirebaseApp.configure()`, service ownership, dependency injection. |
| `hooprTests/UserProfileTests.swift` | Pins the model against the stored document shape. |

### Architectural rules this establishes

- **Firebase types stay in the service layer.** `AuthService` is the only file
  importing `FirebaseAuth`; `UserProfileService` is the only one touching
  Firestore. Models and ViewModels see `UserProfile` and `UserProfileError`,
  never a `DocumentSnapshot`.
- **Services own their own subscriptions.** `UserProfileService` subscribes to
  `AuthService` directly, so one listener serves the whole session. It is *not*
  driven by a ViewModel — a ViewModel's lifetime is tied to a screen, which
  would tear the listener down every time that screen closed.
- **Writes are explicit field maps**, never whole-object encodes. This is what
  keeps `createdAt` from being clobbered and keeps server timestamps
  server-assigned.
- **Constructor injection throughout** — services are `@StateObject`s in
  `hooprApp` passed down as plain `let`s. No `@EnvironmentObject`.

---

## 7. Security model

Rules live in `firestore.rules`; the update rule and its rationale are in
`DATABASE_SCHEMA.md`. In effect: you can only write your own document, you can
only change `userName` and `homeCourtId` (+ `updatedAt`), `id` and `createdAt`
are immutable **even against a hand-crafted request**, and reads are open to any
signed-in user because match rosters will need to resolve names later.

---

## 8. Verifying it works

**End-to-end:**
1. Sign in → greeting shows a name instead of "there".
2. Firebase console → `users/` contains a document keyed by your Auth uid.
3. Edit the name in Profile → greeting updates immediately.
4. Relaunch the app → the name persists.
5. In the console, confirm `updatedAt` moved but **`createdAt` did not**.

**Unit tests** (`hooprTests/UserProfileTests.swift`) run through
`Firestore.Decoder` — the same decoder the service uses — so a field rename in
the console or the model fails a test instead of silently blanking the UI. They
cover the full stored shape, a minimal document, a missing `userName` (must fail
loudly), unresolved server timestamps decoding as nil, and the name-length and
blank-name bounds shared with the rules.

**Troubleshooting:**

| Symptom | Cause |
|---|---|
| "the server refused the request… rules are probably not deployed" | A **read** was denied: rules not deployed, or deployed to the wrong project. The listener is already re-attaching on a backoff |
| "The server wouldn't accept that change" | A **write** was denied. Not a deployment message on purpose — the client already validated it, so suspect the rules' own conditions |
| Saving a new field fails with `permission-denied` | The field isn't in `hasOnly([...])`, or the rules weren't redeployed |
| Greeting stuck on "there" | No profile document and provisioning failed — check for a `permission-denied` in the log |
| "stored in an unexpected format" | Document field names drifted from the model (e.g. `userName` renamed) |
| Home Court reads "Unknown court" | The stored `homeCourtId` no longer matches any court in the bundled dataset |
| Crash on launch in `Auth.auth()` | `FirebaseApp.configure()` isn't running before services are constructed |

Simulator logs about `hapticpatternlibrary.plist`, `GeoGL`/`GeoCodec`
allocators, `default.csv`, or `CAMetalLayer` zero drawable size are unrelated
noise from the keyboard and MapKit — not Firestore.

---

## Invariants

- One profile listener per session, owned by `UserProfileService`, guarded by
  `observedUID`.
- Provisioning must stay idempotent — it runs on every sign-in.
- Writes are explicit field maps containing only the changed field plus
  `updatedAt`.
- Sign-out must clear `observedUID`, `currentProfile` and `errorMessage`.

## See also

- `DATABASE_SCHEMA.md` — the stored shape and the rules that enforce it.
- `../ARCHITECTURE.md` — startup order and the vendor boundary.
- `../UI_SHELL.md` — how the profile screen is presented.
