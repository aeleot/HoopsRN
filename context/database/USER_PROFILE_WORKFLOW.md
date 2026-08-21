# hoopsRN — User Profile Workflow

**Scope:** —
**Verified:** 2026-08-21 @ da44193

How the app connects to Firestore and what happens at runtime between someone
signing in and a rendered profile. This is the first hoopsRN feature backed by a
real database, so it also establishes the patterns `games` and `friendships`
both followed.

**This entry owns no source paths, deliberately.** It's a narrative across
`AuthService`, `UserProfileService`, `ProfileViewModel` and `Views/Profile/`,
every one of which is owned by `ARCHITECTURE.md` or `UI_SHELL.md` — scopes may
not overlap, so it declares none and is re-checked by hand every pass, like
`GAPS.md`. It previously carried a scope of un-resolvable path fragments, which
made the drift check report it "current" while it went two weeks stale.

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

That read-access row is the reason **the email is never copied into Firestore**.
Auth keeps it private to the account; a `users` document is visible to every
signed-in player, and Firestore can't hide one field of a readable document.
The profile screen's Email row reads `AuthService.currentUser` directly, so
nothing was lost by not storing it — see `DATABASE_SCHEMA.md`.

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
`userName` (1–50 chars, editable, not unique), `userNameLower` (its lowercased
mirror, derived on write so player search has something to prefix-match),
`homeCourtId` (a `Court.id`, editable, deleted when cleared),
`preferredRadius` (1–50 miles, editable, defaults to 5), `favoriteCourtIds`
(starred courts), `createdAt` (write-once)
and `updatedAt` (refreshed on every write).

`userName`, `homeCourtId`, `preferredRadius` and `favoriteCourtIds` are the only
fields a person can change — plus `userNameLower`, which nobody edits directly:
it's written in the same field map as `userName`, through
`UserProfile.searchKey(_:)`. Enforced server-side, not by convention.

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
firestore.indexes.json   → composite indexes (two, both for `games`)
```

**d. Deploying rules** — the repo is authoritative; the console is not. Redeploy
after any rules change:

```bash
firebase deploy --only firestore:rules,firestore:indexes
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
   `aeleot11`, or `"Hooper"` if Auth has no email), `userNameLower` derived from
   it, and `createdAt`/`updatedAt` as `FieldValue.serverTimestamp()`. The email
   is *read* from Auth to seed that name and then deliberately not stored.
5. The write triggers the listener, which decodes into `UserProfile` and
   publishes it. The UI updates reactively — no manual refresh.
6. **The search-key backfill runs on that same snapshot.** If the decoded
   profile has no `userNameLower`, `backfillSearchKeyIfNeeded` writes one — see
   below. It has to happen here, on the owner's own client, because the update
   rule is owner-only.

A snapshot for a document that doesn't exist is **not** treated as an error —
provisioning may still be in flight, so `currentProfile` just stays nil.

Provisioning exists because accounts created *before* this feature shipped have
no profile document. Rather than a one-off migration, every sign-in self-heals.

### The `userNameLower` backfill — the same pattern, a second time

Player search needs a lowercased mirror of the display name to prefix-match on.
Accounts provisioned before that field existed don't have one, and a profile
with no `userNameLower` is **invisible to name search forever** — the range
query has nothing to match.

There is no server-side fix available: the update rule is owner-only, so no
client can backfill another account, and the project is on the Spark plan with
no Cloud Functions. So the migration is the same self-healing shape as
provisioning — each account writes its own key the next time its owner opens the
app.

Two guards make it safe to run on every snapshot:

- The write produces a snapshot whose `userNameLower` **is** set, so the
  `== nil` check stops it the second time round.
- `didBackfillSearchKey` covers a *failed* attempt, which produces no such
  snapshot — one try per session rather than a write retried on every snapshot.
  It resets in `startObserving`, so the next sign-in tries again.

It fails silently by design: the user didn't ask for it and can do nothing about
it. **The consequence is a real one and belongs in any conversation about
search:** until an account's owner has launched a build containing this, that
person can't be found by name — only by user ID, which reads the document
directly.

### The edit cycle

The profile screen shows eight rows in two sections. Only **three** go through
`ProfileViewModel.EditableField` and its `.sheet(item:)`, and that distinction
is the point: `EditableField` means "a field of the profile *document*", so
everything sharing its in-flight and failure handling is a Firestore write.

| Row | Section | Source | Editable |
|---|---|---|---|
| Home Court | Your Game | `homeCourtId` → resolved via `CourtService` | yes — `EditableField`, searchable court picker |
| Favorites | Your Game | `favoriteCourtIds`.count | no — starred from the map; the profile only counts them |
| Search Radius | Your Game | `preferredRadius` | yes — `EditableField`, slider (1–50 miles) |
| Username | Account | `userName` | yes — `EditableField`, text sheet |
| Email | Account | Firebase Auth | no — changing it needs an Auth re-authentication flow |
| Password | Account | *(a `••••••••` fiction)* | yes, but **outside `EditableField`** — sends a reset link via Auth, writing no document |
| Appearance | Account | `UserDefaults` | yes, but **outside `EditableField`** — device-local, no network round trip |
| Joined | Account | `createdAt` | no — write-once by design |

The two outside `EditableField` carry their own `@State` + `.sheet(isPresented:)`,
and the password reset additionally carries its own
`isSendingPasswordReset` / `didSendPasswordReset` / `passwordResetError`.

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
| `Views/Profile/ProfileView.swift` | The full-screen profile. **Two panes** — Profile and Friends — over one scroll view, with a `ProfileTopBar` safe-area inset. There is no orange header any more; see `../UI_SHELL.md`. |
| `Views/Profile/ProfileIdentity.swift` | `ProfileIdentityBlock` (avatar, `@handle`, copyable uid) and `ProfileTopBar`. |
| `Views/Profile/ProfileRow.swift` | One label/value row, plus `ProfileActionRow`. `onTap: nil` renders it read-only. (This replaced `ProfileFieldRow.swift`, which no longer exists.) |
| `Views/Profile/ProfileEditSheets.swift` | The username editor, the searchable home-court picker, the radius slider, the appearance picker and the password-reset sheet. |
| `Views/MainTabView.swift` | Greeting reads `currentProfile?.userName`; presents `ProfileView` **in place of** the tab interface. |
| `hooprApp.swift` | `FirebaseApp.configure()`, service ownership, dependency injection. |
| `hooprTests/UserProfileTests.swift` | 17 cases: the stored document shape, the radius coercion ladder, and name validation. |

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
only change `userName`/`userNameLower`, `homeCourtId`, `preferredRadius` and
`favoriteCourtIds` (+ `updatedAt`), `id` and `createdAt`
are immutable **even against a hand-crafted request**, both create and update
carry a key allowlist so no unvetted field can be stored at all, and reads are
open to any
signed-in user — which is what lets match rosters resolve names, and what friend
search is built on.

---

## 8. Verifying it works

**End-to-end:**
1. Sign in → greeting shows a name instead of "there".
2. Firebase console → `users/` contains a document keyed by your Auth uid.
3. Edit the name in Profile → greeting updates immediately.
4. Relaunch the app → the name persists.
5. In the console, confirm `updatedAt` moved but **`createdAt` did not**.

**Unit tests** (`hooprTests/UserProfileTests.swift`, 17 cases) run through
`Firestore.Decoder` — the same decoder the service uses — so a field rename in
the console or the model fails a test instead of silently blanking the UI. They
cover the full stored shape, a minimal document, a missing `userName` (must fail
loudly), unresolved server timestamps decoding as nil, a document still carrying
the purged `email` field, the six-case radius coercion ladder, and the
name-length and blank-name bounds shared with the rules.

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
- `EditableField` means a write to the profile *document*. An edit that doesn't
  touch Firestore — appearance, the password reset — stays outside it and brings
  its own presentation state.
- The `userNameLower` backfill stays idempotent and once-per-session. It is the
  entire migration; there is no server-side one.

## See also

- `DATABASE_SCHEMA.md` — the stored shape and the rules that enforce it.
- `../ARCHITECTURE.md` — startup order and the vendor boundary.
- `../UI_SHELL.md` — how the profile screen is presented.
