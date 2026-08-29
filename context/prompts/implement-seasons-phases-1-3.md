# Implement — Seasons Phases 1–3 (squads, squad UI, matchmaking core)

Build the `squads` backend, the Seasons tab that renders it, and the
matchmaking core underneath — Phases 1, 2 and 3 of
`context/plans/SEASONS.md`.

**Read `context/plans/SEASONS.md` in full before writing anything.** It is the
authoritative spec: the schema, the rules blocks, the claim transaction, the
scoring model, and the reasoning behind each. This prompt tells you *how to
execute* that plan correctly and in the right order; it does not restate the
design. Where anything here seems to conflict with the plan, **the plan wins —
but stop and flag the conflict** rather than silently picking a side, because a
conflict means one of the two documents is stale.

> **Run these as three separate sessions, in this order, committing between
> each.** Each phase below is independently shippable, independently revertable,
> and leaves the app working. Attempting all three in one session will exhaust
> context somewhere in Phase 3's test suite and produce drift in Phase 1's rules
> — which is the expensive half to get wrong.

---

## Preflight — the Phase 0 gate

`SEASONS.md` §6 makes Phase 0 a gate. Two of its findings block work below, and
**one of them requires infrastructure this repo does not have yet.**

`firebase.json` declares only `firestore.rules` and `firestore.indexes.json`.
There is **no emulator configured**, and `FirestoreRulesParityTests` says so in
its own doc comment ("Full rules coverage needs the Firebase emulator, which
isn't wired up here"). So:

| Gate item | Blocks | If not done |
|---|---|---|
| `Court.city` is non-empty and consistently cased for every court in the dataset | Phase 1 (`region` field) | **Stop.** Report the offending courts. Do not invent a fallback region. |
| Firestore emulator wired into `firebase.json`, claim transaction proven with two concurrent clients | Phase 3 only | Phases 1–2 may proceed. Phase 3 **stops** at the `MatchmakingService` boundary — see Phase 3 scope. |

**Verify the region key before starting Phase 1.** It is one command and it
decides a stored field:

```bash
python3 -c "import json;d=json.load(open('hoopr/Resources/courts.json'));c=[x.get('city') for x in d['courts']];print({k:c.count(k) for k in set(c)})"
```

If any court has an empty, `null`, or inconsistently-cased city, **stop and
report** — `region` is written into `squads`, `matchTickets` and `seasonGames`,
and a bad key silently partitions the matchmaking pool into groups that can
never see each other. That is a failure with no error message, which is the
worst kind.

> **Run 2026-08-28 — this gate item is closed.** The command above returns
> `{'Durham': 55, 'Raleigh': 53, 'Chapel Hill': 43, 'Cary': 26, 'Apex': 22,
> 'Morrisville': 15}`: 214 courts, six cities, no empty or `null` value, casing
> consistent. `Court.city` is a usable `region` key. Re-run it only if
> `courts.json` is regenerated — `tools/build_courts.py` or
> `tools/fetch_city_courts.py` would both invalidate this result.

---

## Invariants — all three phases

These are not style preferences. Each one is load-bearing, and the reason is
given because a rule without a reason gets "improved."

**Xcode target membership is automatic.** `project.pbxproj` is
`objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup`. Any `.swift`
file created under `hoopr/` or `hooprTests/` is picked up by the target with no
project-file edit. **Do not hand-edit `project.pbxproj`** — you will corrupt a
synchronized group and the project will stop opening.

**Every test in this suite targets a `nonisolated static` pure function.**
Grep confirms it: no test file instantiates a service, and there are no service
stubs anywhere in `hooprTests/`. Coverage comes from pulling logic out as pure
statics on models and view models — `Game.validate`, `Game.calculateStreak`,
`FriendsViewModel.looksLikeUserId`, `CourtSearch`.

> **Consequence you must design around:** any logic that cannot be reached as a
> pure function is, in this project, untestable. Before writing a method that
> takes a service or touches Firestore, ask whether its *decision* can be a
> static that takes plain values. If it can, it must be. This is why
> `MatchRules` is specified as a free function over two structs rather than a
> method on `MatchmakingService`.

**The Firebase vendor boundary holds.** Firebase imports appear **only** in
`hoopr/Services/`. Models are `nonisolated struct`, `Identifiable, Sendable,
Codable, Hashable`, and mirror the document ID into an `id` field so they decode
without `@DocumentID` (which would drag a Firebase type into `Models/`).

**No `@EnvironmentObject`.** Every view model takes its dependencies through
`init()`. Cross-collection joins live in view models, never services — services
have no dependencies on each other.

**Server timestamps are pinned, not requested.** Write
`FieldValue.serverTimestamp()` client-side and assert `== request.time` in the
rules. A field a client can choose is a field a client can forge.

**Run tests with the target filter, always:**

```bash
xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests
```

Without `-only-testing:hooprTests` the UI test runner fails to launch
(`RequestDenied` from SpringBoard) and **masks real unit failures** — a green-
looking run that proved nothing.

**Dry-run rules before claiming they work:**

```bash
firebase deploy --only firestore:rules,firestore:indexes --dry-run
```

---

# Phase 1 — Squads backend

**No UI. Nothing in `Views/`, nothing in `MainTabView.swift`.** Verified by
tests and a rules dry-run, not by a screen.

## Build

- `hoopr/Models/Squad.swift` — `Squad`, `SquadFormat`, `SquadError`, and the
  pure helpers: name validation, roster bounds, `isLeader(_:)`,
  `hasMember(_:)`, and the icon/colour allowlists. Plan §2.
- `hoopr/Models/SquadInvite.swift` — the model and `id(for:_:)`, mirroring
  `Friendship.id(for:_:)` exactly. Plan §2.
- `hoopr/Services/SquadService.swift` — follow `FriendService.swift` structurally:
  own `AuthService` subscription via Combine, `lazy var database`, private
  `Collection` / `Field` / `ListenerKey` / `Limit` enums, per-document
  `decoded(_:)`, `handle(_:error:listener:describing:)`,
  `report(_:whileDoing:context:)`, `mapped(_:)`, and a `nonisolated static
  message(for:whileDoing:context:)`. `FailureContext` lives in
  `hoopr/Services/ListenerSupervisor.swift`.
- The `squads` and `squadInvites` blocks appended to `firestore.rules`.
- Any composite index the listeners need, in `firestore.indexes.json`.
- `hooprTests/SquadTests.swift` — decoding and every pure helper.
- Extensions to `hooprTests/FirestoreRulesParityTests.swift` — see below.

**Do not build:** `SeasonsTab`, `SquadViewModel`, `SquadCrest`, `MatchTicket`,
`MatchRules`, `MatchmakingService`, `SeasonGame`, or any change to
`MainTabView`/`RootView`/`hooprApp.swift`. Those are Phases 2–4.

## The three update paths must be three separate rules

`firestore.rules` already splits `users` into a profile-edit path and a
stats path, and `games` into a roster path and a completion path, so that one
write can never smuggle in another's fields. `squads` gets the same treatment:

1. **Leader edit** — `name`, `nameLower`, `iconKey`, `colorKey`, `updatedAt`.
   Leader only. Must not touch `memberIds`.
2. **Self-join** — `memberIds` diff is exactly the caller's own uid (added),
   gated on `exists()` of the matching `squadInvites` document, and bounded by
   the format's roster ceiling.
3. **Self-leave** — `memberIds` diff is exactly the caller's own uid (removed),
   and the caller is **not** the leader. The leader's exit is disbanding, the
   same way a `games` host's exit is cancelling.

Reuse the membership-diff idiom from the `games` update rule verbatim —
`.toSet().difference(...)` in both directions, plus the no-duplicates check.
**The duplicate check is not optional:** without it a roster of
`['me','me','me']` reads as no change at all to a set comparison, which is
exactly the hole the `games` rule documents.

The `squadInvites` create rule requires an accepted friendship. Compute the
ordered pair ID in the rules with a ternary, matching `Friendship.id(for:_:)`.

## Extend the parity test — do not skip this

`FirestoreRulesParityTests` reads the real `firestore.rules` from the source
tree via `#filePath` and asserts the Swift constants still agree with it. Phase 1
introduces four newly-mirrored values, and each needs a test in the same style:

- squad name length bounds
- roster size bounds per format
- the `format` allowlist
- the `iconKey` / `colorKey` allowlists

Follow the existing pattern: **extract the value from the rules with a regex,
compare it to the Swift constant, and fail naming both copies.** Do not
string-match a whole expression — the existing `testStatusRuleMatchesSwift`
deliberately rebuilds the rule from its parts so a reformat doesn't fail but a
behaviour change does. Match that rigour.

## Done when

A squad can be created, invited to, joined, left, and disbanded — proven by
`SquadTests` for the pure logic and a rules dry-run for the write paths. The app
builds and every pre-existing test still passes. No screen has changed.

---

# Phase 2 — Squads UI

**No matchmaking.** The tab renders squads and says matchmaking is coming.

## Build

- `hoopr/Views/Seasons/SeasonsTab.swift` — screens 1 and 2 from plan §5.
- `hoopr/Views/Seasons/CreateSquadSheet.swift` — screen 3.
- `hoopr/Views/Seasons/SquadDetailView.swift` — screen 9.
- `hoopr/Views/Seasons/SquadCrest.swift` — **one view with a size parameter**,
  not five drawings. Plan §5.
- `hoopr/ViewModels/SquadViewModel.swift` — joins `SquadService` to
  `FriendService` for the invite picker. This join is why it is a view model
  and not a service method.
- `MainTabView.swift` — a fourth `Tab`, `trophy.fill`, after Runs.
- `hooprTests/SquadViewModelTests.swift` and additions to
  `hooprTests/ThemeContrastTests.swift`.

## Styling is not freehand

Use `Color.hoopr*` **roles** from `Theme.swift`, `.hooprFont(_:weight:)` from
`Typography.swift`, and `.cardChrome()` for card surfaces. There are no literal
colours left in `Views/` — do not be the first to add one, or the appearance-
awareness mechanism stops working.

**Every squad palette colour goes through `ThemeContrastTests` in this same
commit.** `GAPS.md` already tracks `hooprOrange`-as-foreground failing AA in
light mode; the squad palette is six to eight new colours used as fills behind
glyphs and text. Shipping them untested grows that gap list by eight entries in
one stroke. If a colour fails, retune it or pick a different `onCrest`
foreground — do not add it to the gap list.

Present sheets with `sheet(item:)`, never `isPresented` — the house convention,
and the one that survives a rapid re-tap without going inert.

## Check the tab bar at large Dynamic Type

Four tabs is the practical ceiling. Before fixing the label, render the tab bar
at `.accessibility3` and confirm "Seasons" does not truncate. If it does, use
"Squad" and say so in the commit message — do not add `minimumScaleFactor`, which
is the thing the native tab bar was adopted to stop needing.

## Done when

A user can create a squad, invite friends to it, see it, and open its detail
view. The Seasons tab states plainly that matchmaking is not built yet — an
honest empty state, not a disabled button with no explanation.

---

# Phase 3 — Matchmaking core

**No `SeasonGame`, no game creation, no game UI.** Phase 3 ends when a claim
succeeds. Phase 4 turns a claim into a game.

## Build

- `hoopr/Models/MatchTicket.swift` — the model and its pure helpers.
- `hoopr/Models/MatchRules.swift` — **the pure scorer. This is the heart of the
  phase.** A free function over two `MatchTicket`s plus a court lookup, an
  anchor, and `now`. No Firestore, no service, no main actor.
- `hoopr/Services/MatchmakingService.swift` — pool listener, scan, claim
  transaction, jitter and backoff.
- The `matchTickets` rules block, including the stale-claim re-claim clause.
- The `(region, format, status, expiresAt)` composite index.
- `hooprTests/MatchRulesTests.swift` — **the heaviest test suite in this plan.**

## MatchRules must be pure, and this is why

The invariant above is not decoration here. `MatchRules` is the one piece of
this feature whose correctness cannot be checked by looking at a screen: a
subtly wrong score produces a *plausible* match, not a visible bug. It gets real
coverage only if it is a static function over plain values.

Signature, from plan §1:

```swift
enum MatchRules {
    static func candidate(
        for mine: MatchTicket,
        against theirs: MatchTicket,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D,
        now: Date
    ) -> MatchCandidate?
}
```

Required coverage — each is a named test, not a loop:

- every hard rule rejecting on its own, in isolation
- **disjoint `memberIds`** — a shared player must reject. A person cannot play
  themselves, and this is the rule most likely to be quietly dropped
- soft-rule *ordering*: given three candidates, the expected one ranks first
- relaxation over time: the same pair rejects at t=0 and matches at
  t=`fullRelaxation`
- window arithmetic **across midnight**, and across a DST boundary
- stale claim: `claimed` with an old `claimedAt` is a candidate; a fresh one is not
- empty pool, self-match, expired ticket

## The claim transaction

Follow `GameService.mutateRoster` for shape: `database.runTransaction`, an
`errorPointer` on the read failure path, and a raw-value outcome enum carried
out of the block because `runTransaction` hands back `Any?`. Re-check
`MatchRules` **inside** the transaction — the pool snapshot that produced the
candidate may be seconds stale.

**Do not implement retry-on-transient-error yourself.** `ListenerSupervisor`
owns that for the pool listener. The claim's own retry is a different thing —
bounded at three attempts, then a 15s poll — and it is about *contention*, not
network health. Keep them separate.

## If the emulator gate is not closed

`SEASONS.md` §1 rejects `getAfter()` specifically because it must be proven
before anything is built on it, and the same standard applies to the claim
race itself. If the emulator is not wired up and the two-client test has not
been run:

- **Build `MatchTicket`, `MatchRules` and its full test suite anyway.** They are
  pure, they are the majority of the phase's value, and they depend on nothing.
- **Stop before `MatchmakingService`'s claim transaction.** Report that the gate
  is open and what it would take to close it.

Do not ship an unverified claim transaction and describe it as working. A race
condition that has never been raced is a claim, not a result.

## Done when

`MatchRulesTests` passes with the coverage above, and — gate permitting — two
simulator instances queue and exactly one claims the other, verified against the
emulator. No `seasonGames` document exists yet.

---

## Error handling

Do not improvise a failure path. Each of these has a house answer:

| Situation | Required response |
|---|---|
| `permission-denied` on a **read** | The listener query was shaped to match the read rule, so a refusal means the deployed ruleset isn't this repo's. Surface `FailureText.rulesNotDeployed(loading:)`. The supervisor is already re-attaching. |
| `permission-denied` on a **write** | The client validated first, so the server rejected something the client thought was legal — stale state, or a real authorization bug. Say the state may have changed. **Never blame deployment here**; it sends the reader to the wrong file. |
| Transient network on a listener | `ListenerSupervisor` handles it. Call `recordFailure(for:)` / `recordSuccess(for:)` and set `isRecovering`. **Do not add a second retry loop.** |
| `failed-precondition` | A composite index is missing or still building. Map to `.indexRequired` and add the index to `firestore.indexes.json`. |
| A document fails to decode | Skip that document, log it with `logger.error`, keep the rest of the list. One drifted row must not blank a screen — see `GameService.decoded`. |
| Claim transaction loses the race | Expected, not an error. Re-scan and take the next candidate. **Do not surface a message to the user** — losing a race is invisible by design. |
| Claim transaction fails three times | Back off to a 15s poll. Surface a quiet "still looking" state, not an error banner. |
| A required model field is absent from Firestore | Fail the decode for that document rather than defaulting. A silent default writes a value nobody chose. |
| Rules dry-run fails | Fix the rules before touching client code. A ruleset that doesn't compile can't be deployed, and every write will read as `permission-denied`. |

---

## Wait vs. stop

**Wait for input — ask, then hold — if:**

- `Court.city` is inconsistent (Preflight). The region key is a stored field and
  guessing it partitions the pool invisibly.
- A plan decision reads two ways and the readings produce different schemas.
  Quote both readings; do not pick one.
- The squad colour palette cannot clear AA without changing `hooprOnBrand` or
  another shared Theme role. That is a design decision with app-wide reach.

**Stop and report — do not retry — if:**

- `project.pbxproj` needs editing to make a file compile. It does not; a
  synchronized group picks files up automatically. If a file genuinely isn't
  compiling, something else is wrong and editing the project file will make it
  worse.
- A rules change would require weakening an existing `games`, `users`, or
  `friendships` rule. Nothing in Phases 1–3 needs that. If it seems to, the
  design has drifted.
- You find yourself needing a Cloud Function. `SEASONS.md` §0 exists precisely
  because there isn't one; re-read it rather than routing around it.
- Tests fail in a way that suggests the pre-existing suite was already broken.
  Report the baseline before changing anything.

---

## Chain-of-thought

Before writing the `firestore.rules` block in Phase 1, state:

1. Who may write each field, and which of the three update paths carries it
2. What invariant the membership diff enforces, and what breaks without the
   duplicate check
3. Which existing rule you are copying the idiom from

Before writing `MatchRules` in Phase 3, state:

1. Which rules are hard (reject) and which are soft (score), and why each sits
   where it does
2. What `relaxation` widens, and what it must **never** widen
3. How `courtId` and `scheduledTime` are derived, and which server-side check
   makes a modified client harmless

Then write the code.

---

## Model recommendation

| Phase | Model | Why |
|---|---|---|
| 1 | **Opus** | New collection, three-path rules, and parity-test extensions. Rules mistakes surface as `permission-denied` at runtime, not as compile errors. |
| 2 | **Sonnet** | SwiftUI against an established design system with a clear spec. Escalate to Opus only if the contrast work forces a Theme change. |
| 3 | **Opus** | Concurrency, transaction semantics, and a scoring function whose bugs are plausible-looking rather than visible. |

---

## Test cases — these verify the prompt, not just the code

**Phase 1**
1. A squad document decodes into `Squad` with every field populated; a document
   missing `memberIds` fails the decode rather than defaulting to `[]`.
2. `FirestoreRulesParityTests` fails if the roster ceiling is changed in
   `firestore.rules` but not in `Squad` — and the failure message names both
   copies.
3. A self-join write whose `memberIds` diff contains a uid other than the
   caller's is rejected by the rules dry-run.

**Phase 2**
1. `SquadViewModel` with three friends and one existing member offers exactly
   two invitable people — the member is excluded, and so is the signed-in user.
2. Every squad palette colour clears AA against its `onCrest` foreground in both
   light and dark, asserted in `ThemeContrastTests`.
3. The Seasons tab with no squad renders the create affordance, not an error
   state or a spinner.

**Phase 3**
1. Two tickets sharing one `memberId` produce `nil` from `MatchRules.candidate`,
   at every relaxation value including 1.0.
2. A pair that fails the court-radius rule at t=0 produces a candidate at
   t=`fullRelaxation`, and the chosen court is inside the home ticket's
   `courtIds` in both cases.
3. A ticket whose window spans midnight overlaps correctly with one starting at
   23:30 the same evening.
