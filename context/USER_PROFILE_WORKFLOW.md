# Hoopr — User Profile Workflow

How the app connects to Firestore, what it stores, and what happens at runtime when someone signs in.

This is the first feature in Hoopr backed by a real database, so it also establishes the patterns every later collection (matches, queues) should follow.

---

## 1. Why there's a profile at all

Firebase Auth already knows *who you are* — it issues a uid and holds your email. It does **not** hold anything other players should see.

Two separate layers, deliberately:

| | Firebase Auth | Firestore `users/{uid}` |
|---|---|---|
| Owns | Identity + credentials | App-owned profile data |
| Provides | `uid`, `email` | `userName`, and future profile fields |
| Who can read it | Only the account itself | Any signed-in user |
| Managed by | `AuthService` | `UserProfileService` |

Before this, the greeting guessed a name by slicing the email at the `@`. That guess was recomputed on every render, was never stored, and could never be corrected by the user. The profile document replaces it with a real stored value.

---

## 2. Identity: where the ID comes from

**The app does not generate user IDs.** Firebase Auth mints a uid when the account is created (e.g. `Usc2MRkQN5dfFD9YYOTybOrkyuP2`). That uid is used in two places:

```
users/Usc2MRkQN5dfFD9YYOTybOrkyuP2      ← document ID
  └─ id: "Usc2MRkQN5dfFD9YYOTybOrkyuP2" ← duplicated as a field
```

Why reuse the Auth uid instead of a fresh key:

- **Direct addressing** — `users/{uid}` needs no query to resolve a profile.
- **Simpler rules** — `request.auth.uid == uid` compares against the document path itself.
- **Stability** — the uid never changes for the life of the account, and is never reused. Changing your email does not change it.

The `id` field duplicates the document ID so the Swift model decodes without optionals, matching how `Court` is modeled.

---

## 3. Schema

Defined in `DATABASE_SCHEMA.md`. In short:

| field | type | mutable | notes |
|---|---|---|---|
| `id` | string | no | Auth uid, == document ID |
| `userName` | string | **yes** | 1–50 chars, editable, not unique |
| `email` | string? | no | denormalized from Auth, display only |
| `homeCourtId` | string? | — | reserved, never written yet |
| `createdAt` | timestamp | no | server-assigned at creation |
| `updatedAt` | timestamp | yes | server-assigned on every write |

`userName` is the only field a client can ever change. Enforced server-side, not by convention.

---

## 4. How the connection is set up

Four pieces, three of them one-time:

**a. SDK** — `FirebaseFirestore` is linked via SPM (`firebase-ios-sdk` 12.16.0), alongside `FirebaseAuth` and `FirebaseCore`.

**b. Initialization** — `FirebaseApp.configure()` runs at the very top of `hooprApp.init()`, **before any service is constructed**.

> This ordering is load-bearing. `AuthService.init()` calls `Auth.auth()`, which traps if Firebase isn't configured yet. Services are built eagerly in `init()` (because `UserProfileService` needs `AuthService` injected), so configuration cannot be deferred to the app delegate's later `didFinishLaunching` callback. The `AppDelegate` is retained only as a hook for future APNs registration and must **not** configure Firebase a second time.

**c. Project config** (repo root, version controlled):

```
.firebaserc              → project hoopsrn-4f1e9
firebase.json            → points at the rules + indexes files
firestore.rules          → security rules (source of truth)
firestore.indexes.json   → composite indexes (empty; none needed yet)
```

**d. Deploying rules** — the repo is authoritative; the console is not. Redeploy after any rules change:

```
firebase deploy --only firestore:rules
```

Until rules are deployed, a new database denies every read and write, and the app surfaces "Not allowed to access profiles yet."

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
                      └─ ProfileTab shows name + email, allows editing
```

### Sign-in, step by step

1. `AuthService` emits an `AuthenticatedUser` (uid + email).
2. `UserProfileService` sees the change and calls `startObserving`:
   - Attaches a real-time listener to `users/{uid}`.
   - Kicks off `provisionProfileIfNeeded` in parallel.
3. **Provisioning** reads the document once. If it already exists, it does nothing (idempotent — safe on every sign-in). If missing, it writes:
   - `id` — the uid
   - `userName` — seeded from the email local part (`aeleot11@gmail.com` → `aeleot11`), or `"Hooper"` if Auth has no email
   - `email` — only if present; omitted rather than written as null
   - `createdAt` / `updatedAt` — `FieldValue.serverTimestamp()`
4. The write triggers the listener, which decodes the document into `UserProfile` and publishes it.
5. The UI updates reactively — no manual refresh.

Provisioning exists because accounts created *before* this feature shipped have no profile document. Rather than a one-off migration, every sign-in self-heals.

### Editing a field

The profile screen shows four fields. Only two are editable:

| Field | Source | Editable |
|---|---|---|
| Username | `userName` | yes — text sheet |
| Email | Firebase Auth | no — changing it needs an Auth re-authentication flow |
| Home Court | `homeCourtId` → resolved via `CourtService` | yes — searchable court picker |
| Date Joined | `createdAt` | no — write-once by design |

1. Tapping an edit icon calls `beginEditing(_:)`, which sets `editingField` and presents the matching sheet.
2. Saving calls the corresponding service method, which writes **only** that field plus `updatedAt`. `createdAt` is never in the payload.
3. The listener fires with the new value; the greeting and profile screen both update, because they read the same published state.

Clearing a home court writes `FieldValue.delete()`, removing the field rather than storing an explicit null — consistent with how provisioning omits an absent email.

### Sign-out

The listener is removed and `currentProfile` cleared, so no stale data leaks into the next session.

---

## 6. Code map

| File | Responsibility |
|---|---|
| `Models/UserProfile.swift` | The profile struct. **Free of Firebase types**, like `Court`. Decode-oriented — never hand it to `setData(from:)`. |
| `Services/UserProfileService.swift` | The only file that reads/writes `users`. Owns the listener, provisioning, and updates. Translates Firestore errors into `UserProfileError`. |
| `ViewModels/ProfileViewModel.swift` | Profile screen state: field values, which field is being edited, save/cancel, sign-out. Resolves `homeCourtId` to a court name via `CourtService`. |
| `Views/Profile/ProfileView.swift` | The full-screen profile: orange identity header (5/12 of the screen), field list, sign-out. |
| `Views/Profile/ProfileFieldRow.swift` | One label/value row. `onEdit: nil` renders it read-only. |
| `Views/Profile/ProfileEditSheets.swift` | The username editor and the searchable home-court picker. |
| `Views/MainTabView.swift` | Greeting reads `currentProfile?.userName`; presents `ProfileView` **in place of** the tab interface. |
| `hooprApp.swift` | `FirebaseApp.configure()`, service ownership, dependency injection. |
| `hooprTests/UserProfileTests.swift` | Pins the model against the stored document shape. |

### Architectural rules this establishes

- **Firebase types stay in the service layer.** `AuthService` is the only file importing `FirebaseAuth`; `UserProfileService` is the only one touching Firestore for profiles. Models and ViewModels see `UserProfile` and `UserProfileError`, never a `DocumentSnapshot`.
- **Services own their own subscriptions.** `UserProfileService` subscribes to `AuthService` directly, so one listener serves the whole session. It is *not* driven by a ViewModel — a ViewModel's lifetime is tied to a screen, which would tear the listener down every time that screen closed.
- **Writes are explicit field maps**, never whole-object encodes. This is what keeps `createdAt` from being clobbered and keeps server timestamps server-assigned.
- **Constructor injection throughout** — services are `@StateObject`s in `hooprApp` passed down as plain `let`s. No `@EnvironmentObject`.

---

## 7. Security model

Rules live in `firestore.rules`. The important part is the update rule:

```
request.resource.data.diff(resource.data).affectedKeys()
  .hasOnly(['userName', 'homeCourtId', 'updatedAt'])
```

Firestore has no field-level ACLs, so field immutability is hand-built by diffing the incoming document against the stored one. Combined with explicit `id` and `createdAt` equality checks, this means:

- You can only write your own document.
- You can only change `userName` and `homeCourtId` (+ `updatedAt`).
- `id` and `createdAt` are immutable **even against a hand-crafted request** — the client's good behavior is not what's protecting them.
- Reads are open to any signed-in user, because match rosters will need to resolve names later.

---

## 8. Verifying it works

**End-to-end:**
1. Sign in → greeting shows a name instead of "there".
2. Firebase console → `users/` contains a document keyed by your Auth uid.
3. Edit the name in Profile → greeting updates immediately.
4. Relaunch the app → the name persists.
5. In the console, confirm `updatedAt` moved but **`createdAt` did not**.

**Unit tests** (`hooprTests/UserProfileTests.swift`) run through `Firestore.Decoder` — the same decoder the service uses — so a field rename in the console or the model fails a test instead of silently blanking the UI. They cover the full stored shape, a minimal document, a missing `userName` (must fail loudly), and unresolved server timestamps decoding as nil.

**Troubleshooting:**

| Symptom | Cause |
|---|---|
| "Not allowed to access profiles yet" | Rules not deployed, or deployed to the wrong project |
| Greeting stuck on "there" | No profile document and provisioning failed — check for a `permission-denied` in the log |
| "stored in an unexpected format" | Document field names drifted from the model (e.g. `userName` renamed) |
| Crash on launch in `Auth.auth()` | `FirebaseApp.configure()` isn't running before services are constructed |

Simulator logs about `hapticpatternlibrary.plist`, `GeoGL`/`GeoCodec` allocators, `default.csv`, or `CAMetalLayer` zero drawable size are unrelated noise from the keyboard and MapKit — not Firestore.
