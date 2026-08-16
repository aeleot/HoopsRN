# Plan — Live Court Headcounts

**Status:** proposed, not started
**Drafted:** 2026-08-08 @ ae6d436
**Touches:** `firestore.rules`, `firestore.indexes.json`, `hoopr/Models/`,
`hoopr/Services/`, `hoopr/ViewModels/FindAMatchViewModel.swift`,
`hoopr/Views/Tabs/`, `hooprApp.swift` → `RootView` → `MainTabView` injection chain

> `plans/` is not a dictionary entry and carries no `Scope`/`Verified` stamp. A
> plan describes work that hasn't happened; the dictionary describes code that
> has. When a phase below ships, fold what's true into the dictionary entries
> named in "Documentation debt" and strike it from here.

Let a user see how many people are at a court right now, and check themselves
in. This is the app's first piece of **shared, multi-user state** — everything
in Firestore today is single-owner profile data — so it's also where the
patterns for every later social feature get set.

---

## 1. Why this is worth building first

`MapTab` currently answers "where are the courts?" — a question the
bundled dataset already answers offline, with no account required. Headcounts
are the first thing that makes signing in *worth it*: the map stops being a
static directory and starts being a reason to open the app before leaving the
house.

It's also the smallest social feature that stands alone. Rosters, invites, and
game scheduling all need an "is anyone there" primitive underneath them;
headcount is that primitive with no UI beyond a number.

**The cold-start problem is the real risk, not the engineering.** Nobody checks
in when the count always reads zero. This is a product risk to plan around
(seeding, nudges, a low bar to check in), not something the schema fixes.

## 2. Scope

**In scope**

- One active check-in per user, at one court.
- A live count on the court detail card, plus the ability to check in/out.
- Automatic expiry so a forgotten check-in doesn't inflate a count forever.

**Explicitly out of scope for now**

- **Rosters** ("who is here") — needs a name-resolution pass over `users` and a
  privacy decision. The schema below supports it later without migration.
- **Verifying the user is actually at the court.** A check-in is a claim, not a
  measurement. See §8.
- Counters on map pins and list rows — deferred to Phase 3, deliberately.
- Push notifications, game scheduling, history/analytics.

---

## 3. Data model

### Collection: `checkins/{uid}`

**Document ID is the Firebase Auth uid** — the same choice `users` already
makes, for the same reasons (`database/USER_PROFILE_WORKFLOW.md` §2), plus one
more that's specific to this collection:

> **One document per user means one check-in per user, structurally.** You
> cannot be at two courts at once, and checking into a new court overwrites the
> old document rather than creating a second one. Duplicate check-ins,
> leave-then-arrive races, and "clean up the previous court" logic all stop
> existing. There is nothing to enforce because there is nowhere to put a
> second row.

| field | type | required | notes |
|---|---|---|---|
| `userId` | string | yes | Duplicates the document ID, matching `UserProfile.id` and `Court.id`, so the model decodes without optionals. |
| `courtId` | string | yes | A `Court.id` from the bundled dataset. Same caveat as `homeCourtId`: courts aren't in Firestore, so there's no server-side reference to validate against. |
| `checkedInAt` | timestamp | yes | Server-assigned. |
| `expiresAt` | timestamp | yes | Client-supplied, **bounded by the rules**. When the check-in stops counting. |

**Consequence to accept:** overwriting destroys the previous check-in, so there
is no history. Headcount is present-tense only. A future `checkinHistory`
collection can be appended to on write if that's ever wanted — don't try to
keep history in this collection.

### Expiry: `expiresAt` is the contract, TTL is only housekeeping

Two separate mechanisms, and conflating them is the easy mistake here:

1. **The query filters `expiresAt > now`.** This is what makes a count correct.
2. **A Firestore TTL policy on `expiresAt`** eventually deletes the row. This is
   storage hygiene only.

Firestore TTL deletion is **best-effort and can lag well past the expiry
instant**. A stale document is therefore normal, and any code path that counts
documents without the `expiresAt > now` filter will over-report. Treat the
filter as mandatory, not as belt-and-braces.

Default lifetime: **2 hours**, with the rules refusing anything beyond 3. Long
enough for a pickup session, short enough that a forgotten check-in doesn't
misinform someone that evening.

### Index

`firestore.indexes.json` is currently empty. This query —

```
checkins where courtId == X and expiresAt > now
```

— is an equality plus an inequality on different fields, so it needs a
composite index on `(courtId ASC, expiresAt ASC)`. **This is the first entry
that file will ever hold.** The TTL policy is declared as a `fieldOverrides`
entry on `expiresAt`.

> Verify both shapes against current `firebase-tools` docs before writing the
> file — TTL-via-`fieldOverrides` is CLI-version-dependent, and the fallback is
> configuring the policy in the console or via `gcloud`.

---

## 4. Security rules

Appended to `firestore.rules`, which today holds `users` and nothing else.

```
match /checkins/{uid} {
  function isOwner() {
    return request.auth != null && request.auth.uid == uid;
  }

  // Headcounts are public to signed-in users, same reasoning as `users`.
  allow read: if request.auth != null;

  allow create, update: if isOwner()
    && request.resource.data.keys()
         .hasOnly(['userId', 'courtId', 'checkedInAt', 'expiresAt'])
    && request.resource.data.userId == uid
    && request.resource.data.courtId is string
    && request.resource.data.checkedInAt == request.time
    && request.resource.data.expiresAt is timestamp
    && request.resource.data.expiresAt > request.time
    && request.resource.data.expiresAt <= request.time + duration.value(3, 'h');

  // Checking out is a delete — deliberately unlike `users`.
  allow delete: if isOwner();
}
```

Three things worth stating plainly:

- **`checkedInAt == request.time` is how a server timestamp is enforced**, not
  merely requested. A client can't backdate a check-in to look longer-standing.
- **`expiresAt` is bounded server-side.** It's client-supplied out of
  convenience, so a hand-crafted request must not be able to park a check-in at
  a court for a week.
- **`allow delete` is `true` here, where `users` has `delete: if false`.** Not
  an inconsistency: a check-in is ephemeral by nature and checking out is a
  first-class action, whereas account deletion is an unsupported flow.

**Two-step rule applies** (`database/DATABASE_SCHEMA.md`): rules must be
deployed or every write fails `permission-denied` while the client looks
correct.

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

---

## 5. Client architecture

### The vendor-boundary invariant has to change, on purpose

`ARCHITECTURE.md` currently says: *"Only `AuthService` may import
`FirebaseAuth`; only `UserProfileService` may import `FirebaseFirestore`."* A
`CheckInService` breaks that as literally written.

The invariant's *intent* is "Firebase types never escape the service layer,"
which this design keeps. So the invariant should be **rewritten, not
violated silently**:

> Firebase modules may be imported only by files in `hoopr/Services/`. Each
> service owns exactly one collection and translates SDK errors into a domain
> enum before publishing anything upward.

Make that edit as part of the phase that adds the service, so the doc never
describes a rule the code doesn't follow.

### New files

| File | Responsibility |
|---|---|
| `Models/CheckIn.swift` | Firebase-free struct, like `Court` and `UserProfile`. `checkedInAt`/`expiresAt` are `Date?` — a document read back before a `serverTimestamp()` sentinel resolves carries nulls (same reason `UserProfile` does it). |
| `Models/CheckIn.swift` (same file) | `CheckInError`, mirroring `UserProfileError` case-for-case where the meanings match. |
| `Services/CheckInService.swift` | The only file touching `checkins`. Owns listeners, writes, expiry math, error translation. |

### `CheckInService` shape

Follows `UserProfileService` closely — that file is the house pattern for a
Firestore-backed service and there's no reason to invent a second one.

- `@MainActor final class CheckInService: ObservableObject`
- **Subscribes to `AuthService.$currentUser` itself**, not via a view model.
  `ARCHITECTURE.md` is explicit about why: a view model's lifetime is tied to a
  screen, so a screen-driven listener tears down whenever that screen closes.
- Publishes:
  - `myCheckIn: CheckIn?` — the signed-in user's own active check-in, from a
    session-scoped listener on `checkins/{uid}`, guarded by `observedUID`.
  - `headcount: Int` (Phase 2) / `headcounts: [String: Int]` (Phase 3).
  - `errorMessage: String?`
- Methods: `checkIn(courtId:)`, `checkOut()`, `observeHeadcount(courtId:)`,
  `stopObservingHeadcount()`.
- Sign-out clears `observedUID`, both published values, and every listener.

### Counting: listen to documents, don't use `count()`

Firestore's `count()` aggregate is a **one-shot** read — aggregate queries don't
support snapshot listeners. "Live" via `count()` would mean polling.

So: attach a normal snapshot listener to the filtered query and count the
documents client-side. At this app's scale — a handful of people per court, not
thousands — reading the documents is cheap, and it's genuinely live. It also
leaves the door open to rosters with no query change, since the documents are
already in hand.

*(This corrects the `count()`-with-a-listener suggestion raised in discussion.)*

### Injection

`MapTab` and `FindAMatchViewModel` currently take `courtService` +
`locationService` only. `CheckInService` has to be threaded through the same
chain the location work also needs to extend:

```
hooprApp.swift  →  RootView  →  MainTabView  →  MapTab  →  FindAMatchViewModel
```

`MainTabView.swift:114` constructs `MapTab(courtService:locationService:)`
today. **If the `homeLocation` work (which needs `UserProfileService` on the
same chain) is done around the same time, do both init-signature changes in one
pass** rather than editing four files' initializers twice.

`FindAMatchViewModel.select(_:)` — the empty hook at line 92 — is the natural
place to start/stop the per-court headcount listener.

---

## 6. Phases

Each phase is independently shippable and independently revertable.

### Phase 0 — Decisions

Settle §9 before writing code. The expiry window and the check-out model change
the schema; the rest doesn't.

### Phase 1 — Backend only, no UI

`CheckIn` model, `CheckInService`, rules, index, TTL policy. Verify by hand in
the Firebase console: write a check-in from a scratch call, confirm the rules
reject a forged `checkedInAt` and an over-long `expiresAt`, confirm the query
returns it and stops returning it after `expiresAt`.

Ship-check: nothing in the app changes visually, and nothing regresses.

### Phase 2 — Detail sheet: count + check in/out

The court detail card (`courtCard`, `MapTab.swift:300`) grows a count
line and a primary action button. One listener, scoped to the selected court,
started from `select(_:)` and torn down on `dismissDetail()`.

Button states: `Check in` → `Checking in…` (disabled) → `Leave`. Checking into a
different court while already checked in elsewhere silently moves you — that's
the doc-ID-is-uid design doing its job, but the UI should say so rather than
letting the old court's count drop mysteriously.

Empty state matters: "No one here yet" reads better than "0 players" and softens
the cold-start problem.

Ship-check: two accounts, two simulators, one court — the count moves in both
directions, live, without a refresh.

### Phase 3 — Counts across the nearby list and map pins

`CourtRow` and the map annotations get counts. This is where it gets more
expensive: it needs a query over the *visible* courts, chunked by Firestore's
`in`-clause limit (30 values — verify), not one listener per court and not a
query over all 213.

Recommend scoping to `nearbyCourts` (the 5-mile list) rather than the map
viewport, at least initially — it's a bounded, already-computed set, and it
reuses the pipeline in `FindAMatchViewModel` instead of adding viewport
tracking.

Marker tint by occupancy is tempting here; note that the map's `UIColor` tint is
already a known duplicate of `Color.hooprOrange` (`GAPS.md`), so reconcile that
before adding a second hardcoded colour.

### Phase 4 — Later, not now

Rosters with names; auto-checkout via geofence or significant-location change;
"court is hot" notifications; check-in history.

---

## 7. Testing

**Unit** — follow `hooprTests/UserProfileTests.swift`, the only real coverage in
the repo and the established pattern: decode through `Firestore.Decoder`, the
same decoder the service uses, so a field rename fails a test instead of
silently blanking the UI.

| Test | Guards |
|---|---|
| decodes the full stored shape | `Timestamp` → `Date` on both date fields |
| decodes pending server timestamps | An unresolved sentinel reads back null without crashing |
| missing `courtId` fails to decode | Must fail loudly, not render a check-in with no court |
| expiry filtering | A check-in with `expiresAt` in the past is excluded from the count |

That last one argues for keeping the "is this check-in live" predicate as a pure
static function on the model — testable without Firestore, the way
`FindAMatchViewModel.nearby(courts:to:)` is.

**Manual** — two accounts is the only way to see a count that isn't your own.
Two simulators, or one simulator plus the console. Confirm in the console that
`checkedInAt` is server-assigned and that a second check-in at a different court
*replaces* rather than adds.

**Rules** — the repo has no emulator setup today. Worth considering
`firebase emulators:start` for rules tests, since the rules here encode real
security decisions (forged timestamps, expiry bounds) that manual testing checks
poorly. Out of scope for Phase 1; note it rather than pretending it's covered.

---

## 8. Risks and honest limitations

- **A check-in is a claim, not a measurement.** Nothing stops someone checking
  into a court they aren't at. Mitigations (client-side geofence, App Check)
  are all defeatable or heavy; the real defence is that there's no incentive to
  lie at this scale. Revisit only if abuse actually appears.
- **Counts lag reality at the edges.** People leave without checking out, so
  counts skew high until `expiresAt`. The 2-hour window is the tuning knob.
- **Read costs scale with Phase 3, not Phase 2.** A single court's listener is
  trivial. Counts for every nearby court, re-queried as the user moves, is where
  a free-tier quota would first be felt.
- **No Cloud Functions, and that's deliberate.** Denormalized counters would
  need them, which means the Blaze plan. This design stays on the current
  Firebase footprint — no new SPM products either, since `FirebaseFirestore` is
  already linked.
- **Cold start.** Restated because it's the thing most likely to make this
  feature look like a failure despite working correctly.

---

## 9. Open questions

1. **Expiry window** — 2 hours proposed. Shorter is more accurate and more
   annoying; longer is the reverse.
2. **Should checking in be sticky across app launches?** The document survives;
   the question is whether the UI nags ("still at Rockwood?") or stays silent.
3. **Phase 3 scope: nearby list, or map viewport?** The list is cheaper and
   already computed; the viewport is what a user actually looks at.
4. **Does the count show on the pin, or only in the sheet?** Affects whether
   Phase 3 is required for the feature to feel finished, or is a genuine extra.
5. **Rosters — ever?** It changes the privacy posture from "a number" to "your
   name is visible to strangers at a court," which deserves its own decision
   rather than arriving as a Phase 4 afterthought.

---

## 10. Documentation debt

When phases ship, update — don't let the dictionary drift:

| Entry | Change |
|---|---|
| `database/DATABASE_SCHEMA.md` | The `checkins` collection, its rules, the TTL/`expiresAt` split, the first real index. |
| `ARCHITECTURE.md` | The rewritten vendor-boundary invariant; `CheckInService` in the ownership table. |
| `DATA_MODEL.md` | `CheckIn` and `CheckInError`. |
| `MAP_LAYER.md` | Whatever Phase 2/3 adds to the sheet and the annotations. |
| `GAPS.md` | Strike "No occupancy, check-in, game creation…"; strike the `select(_:)` empty-hook line once it's used. |
| `BUILD_AND_CONFIG.md` | `firestore.indexes.json` is no longer empty; the deploy command now includes `firestore:indexes`. |
| `firestore.rules:6` | The header comment still points at the pre-rename path `"hoopr project info/DATABASE_SCHEMA.md"` and calls this "Phase 1: the `users` collection only" — both stale the moment this lands. Already logged in `GAPS.md`. |

## See also

- `../database/DATABASE_SCHEMA.md` — the conventions this collection follows
  (uid as document ID, absent-not-null, the two-step rule).
- `../database/USER_PROFILE_WORKFLOW.md` — the service/listener pattern
  `CheckInService` mirrors.
- `../ARCHITECTURE.md` — injection chain and the vendor boundary being amended.
- `../MAP_LAYER.md` — the sheet state machine the check-in UI lands inside.
