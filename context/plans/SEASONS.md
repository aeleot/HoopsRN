# Plan — Seasons: squads, matchmaking, and recorded results

**Status:** **shipped.** All eight phases (0 through 7) are built, tested and
folded into the dictionary. See §6.
**Drafted:** 2026-08-28 · **Completed:** 2026-08-29
**Touches:** `hoopr/Models/`, `hoopr/Services/`, `hoopr/ViewModels/`,
`hoopr/Views/Seasons/`, `hoopr/Views/MainTabView.swift`, `firestore.rules`,
`firestore.indexes.json`, `hooprTests/`, `firestore-tests/`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a phase below ships, fold what's true into the dictionary
> entries it names and strike it from here.

> **What survives here, and why.** §6's phase list is struck — that was progress
> tracking, and the work is done. §0 through §5 are kept as the **design
> record**: the arguments that produced the schema, not a description of it.
> Each now opens with a pointer to the dictionary entry that owns what actually
> shipped, and where the two disagree **the dictionary is right** — it describes
> code, this describes an intention. §7 and §8 are kept whole: they name
> permanent boundaries and live risks, which are not phase progress and which
> nothing else carries forward.

A fourth tab where a player forms a **squad**, queues it for a **3v3 match**
against another squad, meets them at a court, and records who won — so a squad
accumulates a real W‑L record over a season.

This is the app's first *competitive* surface. Everything before it is
logistics: find a court, join a run, show up. Seasons adds the thing that makes
people come back — a number that goes up.

---

## 0. The block, stated plainly

The open question in the brief was matchmaking. Here is the answer, and it
starts with the constraint that decides it.

### 0.1 There is no server

`hoopr.xcodeproj` links exactly three Firebase products — `FirebaseAuth`,
`FirebaseCore`, `FirebaseFirestore`. There is no `functions/` directory, and
`firebase.json` declares only `firestore.rules` and `firestore.indexes.json`.
The project is on the Spark plan.

**So nothing can wake up, look at a pool of waiting squads, and pair them.**
Every design that begins "the matchmaker assigns you an opponent" is designing
for infrastructure this project does not have. `plans/BACKLOG.md` Track A
already reached this conclusion for solo Queue Up; Seasons inherits it.

What Firestore *does* give us, and what the whole design leans on:

- **Single-document transactions are strictly serializable.** Exactly one
  concurrent writer wins a contested update to one document. That is a
  distributed lock, and it is all a matchmaker's critical section actually
  needs.
- **Security rules can read other documents** via `get()` / `exists()`, so a
  write can be validated against state the client doesn't own.
- **Snapshot listeners are push.** Every queued client learns about every new
  ticket within a second, for free.

Put together: matchmaking cannot be *push* (a server assigns you a match), but
it can be **pull with a lock** — every client watches the same pool, and the
one that wins a one-document race gets to create the match. That inversion is
the design.

### 0.2 GameKit is not the transport, but its model is the right one

The linked `matchmaking-rules` documentation describes Game Center's
rules-based matchmaking: a player enters a **queue** with a **ticket** carrying
declared **properties**, Apple's service evaluates a **rule set** you configure
in App Store Connect to decide which tickets are compatible and how to assign
teams, and criteria **relax as a ticket waits**.

It cannot be used here, for four independent reasons:

1. It requires Game Center authentication — a second identity system alongside
   the Firebase Auth account that already owns every document in this app.
2. Its output is a `GKMatch` — an ephemeral peer-to-peer *networking session*
   between devices that are online at the same moment. Seasons needs a durable
   Firestore document that two squads see hours apart.
3. It has no concept of physical location, a court, or a scheduled real-world
   time. The entire thing being matched on here is geography and availability.
4. It cannot write to Firestore, so the match it produced would still have to
   be persisted by the same client-side path we'd have to build anyway.

**What is worth stealing is the vocabulary and the shape**, and this plan does
so deliberately:

| GameKit concept | Seasons equivalent |
|---|---|
| Queue | `matchTickets` collection, filtered by `region` + `format` |
| Ticket with properties | `matchTickets/{squadId}` — courts, time window, record, roster |
| Rule set (compatibility) | `MatchRules.compatibility(_:_:)` — a pure Swift function |
| Team assignment | Not needed; squads are pre-formed, which is the whole feature |
| Criteria relaxation over time | `relaxation` derived from ticket age, widening radius / record tolerance / window slack |
| Match quality score | `MatchCandidate.score` — ranks the pool, best claim wins |

So the honest framing for the brief: **we are building a matchmaker, not
adopting one.** The good news is that the hard part of GameKit's design — the
rule set — is a pure function over two structs, which is the most testable
thing in this codebase and needs no Firestore at all.

### 0.3 The one insight that makes squad-vs-squad legal

`firestore.rules` enforces a principle across every collection: **a client may
only write its own membership.** The `games` update rule is explicit about it —

```
members(incoming()).difference(members(resource.data)).hasOnly([request.auth.uid])
```

— and `GAPS.md` records the consequence: waitlist promotion is impossible,
because promoting someone means writing *their* uid.

A squad match looks like it violates this. User1's leader commits three people
to a game. But it doesn't, because **the game references squad IDs, not player
uids.** The leader writes one identifier — their own squad's — and the rules
verify leadership with a single `get()` against `squads/{id}`. Nobody's uid is
ever written by anybody else, anywhere in this feature. The existing security
model survives intact.

That is the load-bearing idea. Everything below is consequence.

---

## 1. Data model

> **Shipped.** What is actually stored, and what a client may write, is in
> `database/DATABASE_SCHEMA.md`; the Swift types are in `DATA_MODEL.md`. Read
> those first — this section is the reasoning that produced them.


Three new collections. All follow house convention: the document ID is
mirrored into an `id` field, no Firebase type escapes the service layer,
server timestamps are pinned to `request.time` in the rules rather than merely
requested, and absence is used instead of null.

### 1.1 `squads/{squadId}`

| field | type | notes |
|---|---|---|
| `id` | string | Mirrors the document ID, per `Game.id`. |
| `name` | string | 3–24 chars. |
| `nameLower` | string | Search key, mirroring `UserProfile.userNameLower`. |
| `leaderId` | string | uid. Always present in `memberIds`. |
| `memberIds` | [string] | Leader included. Bounded by `format.maxRoster`. |
| `format` | string | `"3v3"` today. Allowlisted in the rules. |
| `iconKey` | string | SF Symbol name from a curated allowlist. |
| `colorKey` | string | Palette key from a curated allowlist. |
| `region` | string | See §1.4. |
| `createdAt` / `updatedAt` | timestamp | Pinned to `request.time`. |

**No `wins` / `losses` / `gamesPlayed` fields.** This is a deliberate
departure from `UserProfile`'s `completedGameCount`, and it is the single
biggest integrity win available here. A stored counter on a squad you control
is a number you can type. A record **derived** from `seasonGames where
squadIds array-contains {squadId} and status == "confirmed"` is one query, and
it is *arithmetic over documents two different leaders had to agree on*. There
is nothing to forge and no cache to reconcile.

Cost: one extra query to show an opponent's record. At the scale this feature
operates at — tens of squads per city, tens of games per squad per season —
that is nothing. Revisit only if a standings screen makes it hurt, and then
add the cache as an explicitly-untrusted display field, the way
`completedGameCount` already is.

### 1.2 `squadInvites/{squadId}_{uid}`

Structurally identical to `friendships`: **one document per pair**, ID derived
from its own content so a duplicate is impossible rather than merely
deduplicated. The leader creates the invite; the invitee accepts by adding
**themselves** to `squads/{id}.memberIds`. No one ever writes another person's
uid.

| field | type | notes |
|---|---|---|
| `squadId` | string | |
| `uid` | string | The invitee. |
| `invitedBy` | string | The leader, `== request.auth.uid` at create. |
| `createdAt` | timestamp | Pinned. |

Declining, revoking, and consuming an accepted invite are all `delete` — the
same absence-never-null move `friendships` makes with decline/cancel/unfriend.

**The rules require an accepted friendship between inviter and invitee.** It
costs four lines (`exists()` on the ordered pair ID) and it is the difference
between "squads are built from your friends" and "anyone can spam invites at
strangers," which is a live gap on friend requests already (`GAPS.md`).

### 1.3 `matchTickets/{squadId}`

**The document ID is the squad ID**, which structurally enforces one live
ticket per squad — the same trick `friendships/{pair}` uses, and the one
`plans/LIVE_HEADCOUNT.md` proposes for `checkins/{uid}`. There is no
duplicate-entry logic to write because there is nowhere to put a second row.

| field | type | notes |
|---|---|---|
| `squadId` | string | Mirrors the document ID. |
| `leaderId` | string | The only account that may create or edit it. |
| `squadName` | string | Denormalized for the pool UI. |
| `memberIds` | [string] | Denormalized, so the "no shared players" rule needs no extra read. |
| `format` | string | Equality filter on the pool query. |
| `region` | string | Equality filter on the pool query. |
| `courtIds` | [string] | The squad's acceptable courts, 1–8, ordered by preference. |
| `windowStart` / `windowEnd` | timestamp | When they can play. Bounded server-side. |
| `wins` / `losses` | int | Denormalized at queue time for opponent ranking. Display and scoring only — never the record of truth. |
| `status` | string | `open` \| `claimed` \| `matched`. |
| `claimedBy` | string? | Set only by the claim transaction. |
| `claimedAt` | timestamp? | Pinned. Drives stale-claim recovery. |
| `matchedGameId` | string? | The handoff to the waiting squad. |
| `createdAt` | timestamp | Pinned. Ticket age drives relaxation. |
| `expiresAt` | timestamp | Client-supplied, rules-bounded. Queried against. |

> **Decision this plan makes, and `plans/BACKLOG.md` A2 must be updated to
> match.** A2 proposed `queueEntries/{uid}` for solo Queue Up and flagged that
> it overlaps `checkins/{uid}`, calling for a unified `presence/{uid}`. That
> unification stands for the two *player-level* ephemerals. `matchTickets` is
> **not** part of it: its subject is a squad, not a person; its lifecycle is a
> two-party negotiation, not a self-declaration; and its ID space is squad IDs.
> Folding a squad ticket into a per-user presence document would put two
> different subjects in one collection to save a rules block. Keep them
> separate, and record this in `database/DATABASE_SCHEMA.md`.

### 1.4 Region

`Court.city` is the region key for v1 — the bundled dataset is six Triangle
cities and `city` is already on every court. A squad's `region` is the city of
its leader's nearest court at creation time.

This is a placeholder with a known successor: `plans/SCALE_UP.md` S1.1 defines
a real region key for multi-city delivery. When it ships, `region` here becomes
that key and the pool query is unchanged. Say so in the code comment so nobody
has to re-derive it.

### 1.5 `seasonGames/{gameId}`

| field | type | notes |
|---|---|---|
| `id` | string | Mirrors the document ID. |
| `format` / `region` | string | Copied from the tickets. |
| `homeSquadId` / `awaySquadId` | string | Home is the squad whose ticket was claimed. |
| `squadIds` | [string] | `[home, away]`. The array-contains query field. |
| `homeLeaderId` / `awayLeaderId` | string | Denormalized so the write rules need no `get`. |
| `homeSquadName` / `awaySquadName` | string | Denormalized so history survives a disbanded squad. Verified against `squads` at create. |
| `courtId` | string | Must be in the home ticket's `courtIds`. |
| `scheduledTime` | timestamp | Must fall inside the home ticket's window. |
| `status` | string | `scheduled` \| `cancelled` \| `confirmed` \| `disputed`. |
| `arrivedPlayerIds` | [string] | Self-add only. Both squads, one array. |
| `homeReport` / `awayReport` | string? | The squad ID each leader says won. |
| `homeScore` / `awayScore` | int? | Optional, cosmetic. |
| `result` | string? | The winning squad ID. Written **only** when both reports agree. |
| `cancelledBySquadId` | string? | |
| `createdBy` | string | uid of the claiming leader. |
| `createdAt` / `updatedAt` / `confirmedAt` | timestamp | Pinned. |

**Readable by any signed-in user.** Season play is public by design — records,
standings, and an opponent's history are the point of the feature. This is a
deliberate privacy decision and differs from `games`, which is gated on
`isPublic` or roster membership. Record it in
`database/DATABASE_SCHEMA.md` rather than leaving it to be discovered.

---

## 2. The matchmaker

> **Shipped.** `MatchRules` and `MatchTicket` are described in `DATA_MODEL.md`;
> the `matchTickets` rules, the claim and the stale window are in
> `database/DATABASE_SCHEMA.md`. The claim race is *evaluated* in
> `firestore-tests/claim-race.test.mjs`.


### 2.1 The rule set — a pure function

```swift
/// Everything about whether two tickets should play each other, with no
/// Firestore in sight. The `Game.validate` / `CourtSearch` tradition: pure,
/// `now`-injectable, and the single source of truth that both the scan and
/// the tests read.
enum MatchRules {
    static func candidate(
        for mine: MatchTicket,
        against theirs: MatchTicket,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D,
        now: Date
    ) -> MatchCandidate?
}

struct MatchCandidate {
    let ticket: MatchTicket
    let courtId: String
    let scheduledTime: Date
    let score: Double
}
```

**Hard rules** — any failure returns `nil`:

- different squads, and `memberIds` are disjoint (nobody plays themselves)
- identical `format` and `region`
- theirs is `open`, or `claimed` with a `claimedAt` older than
  `staleClaim` (§2.3)
- `expiresAt > now` on both
- window overlap ≥ `format.duration` (60 min for 3v3)
- `courtIds` intersect, after relaxation
- the resulting `scheduledTime` clears `Game.minimumLeadTime`

**Soft rules** — weighted into `score`, higher wins:

| Signal | Why |
|---|---|
| Record proximity, `1 - abs(myWinPct - theirWinPct)` | The competitive-balance rule. The direct GameKit analogue and the one that makes a season feel fair. |
| Travel distance to the chosen court | Measured from `LocationService.homeLocation`, like every other distance in the app. |
| Ticket age (theirs) | Fairness — a squad that has waited longer gets picked first. |
| Window overlap size | More overlap means more scheduling freedom. |

**Relaxation** is a single `Double` in `0...1` derived from *my* ticket's age:

```swift
let relaxation = min(1, now.timeIntervalSince(mine.createdAt) / MatchRules.fullRelaxation)
```

It widens the court radius, the record-proximity tolerance, and the acceptable
window slack. This is GameKit's "criteria expand as you wait," and it is what
makes a thin pool eventually produce a match instead of spinning forever. The
UI says so out loud — *"Widening the search…"* — because a search that silently
lowered its standards would produce a mismatch the user can't explain.

Deriving `courtId` and `scheduledTime` here (rather than negotiating them)
means both clients compute the same answer from the same inputs. But **the
guarantee is not the agreement** — it is that the rules verify the chosen court
is in the home ticket's `courtIds` and the chosen time is inside its window. A
modified client cannot schedule you somewhere you never said you'd go.

### 2.2 The claim — a one-document race

Squad B's client picks the top candidate and runs a **transaction against one
document: squad A's ticket.**

```
runTransaction:
  read matchTickets/{A}
  guard status == "open"  OR  (status == "claimed" AND claimedAt < now - staleClaim)
  guard expiresAt > now
  guard MatchRules still produces a candidate      ← re-checked inside the txn
  write status = "claimed", claimedBy = B, claimedAt = <server>, updatedAt
```

Firestore serializes contested single-document transactions, so **exactly one
claimer wins.** Every loser gets a retry-exhausted failure, re-scans, and takes
the next candidate. There is no double-booking to detect and repair, because
there is no window in which two squads both believe they claimed A.

Rules for that transition:

```
allow update: if isSignedIn()
  && incoming().diff(resource.data).affectedKeys()
       .hasOnly(['status', 'claimedBy', 'claimedAt', 'updatedAt'])
  && incoming().status == 'claimed'
  && incoming().claimedBy != squadId
  && get(/databases/$(database)/documents/squads/$(incoming().claimedBy))
       .data.leaderId == request.auth.uid
  && resource.data.expiresAt > request.time
  && (resource.data.status == 'open'
      || (resource.data.status == 'claimed'
          && request.time > resource.data.claimedAt + duration.value(90, 's')))
  && incoming().claimedAt == request.time;
```

Then B creates the game and marks both tickets `matched`. Neither write is
part of the critical section, so neither needs to be atomic with the claim.

### 2.3 Failure between claim and create

B could crash, lose the network, or be force-quit after winning the claim and
before writing the game. A's ticket would sit `claimed` forever.

**`staleClaim = 90s`**, enforced in three places so they can't disagree: the
scanner treats an older claim as claimable, the rules permit re-claiming it,
and A's own waiting UI reverts to "searching" rather than showing a match that
never arrived. A griefer who claims tickets and never creates games costs the
pool 90 seconds per ticket and nothing else.

### 2.4 Creating the game

```
allow create: if isSignedIn()
  && incoming().createdBy == request.auth.uid
  && incoming().awayLeaderId == request.auth.uid
  && incoming().squadIds == [incoming().homeSquadId, incoming().awaySquadId]
  && incoming().homeSquadId != incoming().awaySquadId
  // Proves the claim was won — this is what authorizes naming another squad.
  && get(.../matchTickets/$(incoming().homeSquadId)).data.status == 'claimed'
  && get(.../matchTickets/$(incoming().homeSquadId)).data.claimedBy == incoming().awaySquadId
  // The court and time must be ones the home squad actually offered.
  && get(.../matchTickets/$(incoming().homeSquadId)).data.courtIds
       .hasAll([incoming().courtId])
  && incoming().scheduledTime > request.time
  && incoming().scheduledTime >= get(.../matchTickets/$(incoming().homeSquadId)).data.windowStart
  && incoming().scheduledTime <= get(.../matchTickets/$(incoming().homeSquadId)).data.windowEnd
  && get(.../squads/$(incoming().homeSquadId)).data.leaderId == incoming().homeLeaderId
  && incoming().status == 'scheduled'
  && incoming().arrivedPlayerIds == []
  && !('result' in incoming()) && !('homeReport' in incoming()) && !('awayReport' in incoming())
  && incoming().createdAt == request.time && incoming().updatedAt == request.time;
```

Rules `get()`s against the same path within one evaluation are cached, so this
is two document accesses, well inside the ten-access ceiling.

B then sets `status = "matched"` and `matchedGameId` on **both** tickets. A's
client is already listening to its own ticket — that field is how a waiting
squad learns it has been matched, on a document it can always read.

> **Considered and rejected: `getAfter()`.** Firestore rules can validate the
> post-commit state of *another* document in the same transaction, which would
> let the claim and the game creation be one atomic step and remove §2.3
> entirely. It was rejected because it makes correctness depend on a
> lesser-used rules primitive interacting correctly with the iOS SDK's
> transaction commit — a thing that has to be proven in the emulator before
> anything is built on it. The two-step design needs only single-document
> transaction semantics, which are the most load-bearing guarantee Firestore
> makes. If Phase 0's spike shows `getAfter()` works cleanly, collapsing the
> two steps is a worthwhile follow-up, not a prerequisite.

### 2.5 Thundering herd

Every queued client sees every new ticket at once. If six squads are waiting
and a seventh appears, all six may claim it simultaneously — one wins, five
burn a transaction.

Mitigations, in order of value: a randomized 0.5–3s jitter before claiming;
claim only the top candidate; on failure re-scan rather than blindly trying
the next; cap at three attempts then back off to a 15s poll. At the scale this
feature will actually see, this is over-engineering insurance, not a hot path.

---

## 3. Results, and why a record is trustworthy

> **Shipped.** The reporting rules, the derived status and the record query are
> in `database/DATABASE_SCHEMA.md` under "Reporting"; `SeasonGame` is in
> `DATA_MODEL.md`. Evaluated against two authenticated leaders in
> `firestore-tests/results.test.mjs`.


`GAPS.md` records the current ceiling honestly: `completedGameCount` is
self-reported, and "a modified client could misreport its own stats." A
competitive record cannot inherit that ceiling unchanged — the whole point of
the number is that other people believe it.

**Mutual confirmation** raises the ceiling as far as a serverless design
allows:

1. After `scheduledTime`, each leader writes **only their own** report field
   (`homeReport` / `awayReport`), naming the squad they say won. The rules pin
   each field to its own leader.
2. When the second report lands and the two **agree**, that same write also
   sets `result`, `confirmedAt`, and `status = "confirmed"`. The rules verify
   `result` equals both reports.
3. When they **disagree**, `status = "disputed"`, no `result`, and the game
   counts for nobody. Either leader may clear their own report and re-enter it,
   which is how a dispute gets resolved — by two people talking, which is what
   actually happens at a court.

So forging a win requires two colluding squads rather than one lying client.
That is not cryptographic integrity and this plan does not claim it is; it is
the same standard a rec league scoresheet meets. State it in
`database/DATABASE_SCHEMA.md` next to the rule.

**The record is a query, not a field** (§1.1). A squad's W‑L is
`seasonGames where squadIds array-contains {squadId} and status == "confirmed"`,
counted client-side by `result`. Disputed and cancelled games are structurally
excluded because they never reach `confirmed`.

---

## 4. Game day without push notifications

> **Shipped.** `SeasonGameNotifications` is in `DATA_MODEL.md`, the vendor
> boundary around `UserNotifications` in `ARCHITECTURE.md`, and arrival in
> `database/DATABASE_SCHEMA.md`. The named limitation is in `GAPS.md`.


The brief asks for a one-hour warning. There is no FCM (not linked) and no
Cloud Function to send from, so a true push is out of reach on the Spark plan.

**`UNUserNotificationCenter` local notifications**, scheduled on each member's
own device from its own `seasonGames` listener:

| Trigger | Copy |
|---|---|
| T−60 min | "3v3 vs {opponent} in an hour — {court}" |
| T−0 | "Tip-off. Tap to mark your squad as arrived." |
| T+90 min | "How'd it go? Record the result." |

Identifiers are `seasonGame:{id}:{kind}` so a cancellation or a stale copy is
removed and replaced rather than duplicated. `AppDelegate` already exists with
a comment naming APNs registration as its future purpose — this is the first
thing to actually use it, though local notifications need no APNs token.

**Named limitation, not a bug:** a client that never launches between the match
being made and the game starting never schedules its notification. Real push
needs Blaze + a Cloud Function; put it in `GAPS.md` when this ships rather than
letting someone rediscover it.

**Arrival** is the existing self-only membership pattern verbatim:
`arrivedPlayerIds` accepts a diff of exactly the caller's own uid, and the
caller must be in one of the two squads' `memberIds` (two `get()`s). Both
squads see each other's check marks live off the same listener — which is
exactly the moment in the brief where User1's squad sees they're first to the
court.

---

## 5. Interface

> **Shipped.** The tab, its screens, the crest and the form guide are in
> `UI_SHELL.md` — including the tab-label decision, which was settled by
> measurement in `TabBarLabelTests`.


A fourth tab, `trophy.fill`, after Runs. Everything below is built on the
existing system — `cardChrome()`, `hooprFont`, Theme colour *roles*, sheets
presented with `sheet(item:)` — so Seasons reads as the same app rather than a
bolted-on mode.

**The crest** is the feature's visual anchor: the squad's SF Symbol on a filled
circle in the squad's palette colour, with the name beside it. It appears at
five sizes — 64pt on the squad home, 44pt on a match card, 32pt in a list row,
24pt in the pool, 20pt in a notification-adjacent inline row — and it is one
`SquadCrest` view with a size parameter, not five drawings.

**The form guide** — the last five results as W/L pills — is the cheapest
possible way to make a record feel like a season rather than two integers.

### Screens

1. **Seasons, no squad.** A hero empty state, not an error. Explains 3v3
   seasons in one sentence and offers "Create a squad."
2. **Squad home.** Crest, record, form guide. Then the one card that matters
   right now — *next match*, *searching*, or *find a match* — and recent
   results beneath it.
3. **Create squad.** Name, icon grid, colour grid, format (3v3 live; 1v1 and
   5v5 shown disabled as "soon", because the schema already carries `format`).
   Then invite friends from the existing friends list.
4. **Queue sheet.** Time window as chips ("Tonight", "Tomorrow evening",
   "Custom") and courts as a multi-select defaulting to the three nearest, so
   the common case is two taps.
5. **Searching.** Live pool count, elapsed time, and an explicit "Widening the
   search" state when relaxation kicks in. Cancellable.
6. **Match found.** Both crests, the opponent's record, court, time, and the
   leader's cancel control.
7. **Game day.** Countdown, court with a map snippet, both rosters with live
   arrival check marks, and "We're here."
8. **Result.** "Who won?" as two large crest buttons, optional score, then a
   waiting / confirmed / *"results don't match"* state.
9. **Squad detail.** Record, form, full game history, roster, leader controls.

### Two things that will bite

- **Colour contrast.** `GAPS.md` tracks `hooprOrange`-as-foreground failing AA
  in light mode. A squad palette is six to eight new colours used as *fills
  behind glyphs and text*. Every one goes through `ThemeContrastTests` in the
  same commit that introduces it, or the gap list grows by eight entries.
- **A fourth tab is a real cost.** Four is the practical ceiling before labels
  start truncating at large Dynamic Type sizes. Check the tab bar at
  `.accessibility3` before committing to the label "Seasons" over "Squad".

---

## 6. Phases — ~~all shipped~~

~~Each phase is shippable and leaves the app working.~~ **All eight shipped
between 2026-08-28 and 2026-08-29.** The phase-by-phase breakdown is struck per
the note at the top of this file; what each one produced now lives in the
dictionary.

| Phase | Shipped | Folded into |
|---|---|---|
| ~~0 — Spike and decisions~~ | `dd90da7` | `database/DATABASE_SCHEMA.md`, `BUILD_AND_CONFIG.md` (the emulator) |
| ~~1 — Squads backend~~ | `54ff8a8` | `database/DATABASE_SCHEMA.md` (`squads`, `squadInvites`), `DATA_MODEL.md` |
| ~~2 — Squads UI~~ | `d6bca0e` | `UI_SHELL.md` (`SeasonsTab`, the crest) |
| ~~3 — Matchmaking core~~ | `a4be2d0` | `DATA_MODEL.md` (`MatchTicket`, `MatchRules`) |
| ~~3.5 — Close the emulator gate~~ | `dd90da7` | `BUILD_AND_CONFIG.md` (the rules suite) |
| ~~4 — Season games~~ | `e4966bd` | `database/DATABASE_SCHEMA.md` (`seasonGames`), `UI_SHELL.md` |
| ~~5 — Game day~~ | `9d6e3f8` | `DATA_MODEL.md` (`SeasonGameNotifications`), `ARCHITECTURE.md` (the second vendor) |
| ~~6 — Results and record~~ | `9ff5968` | `database/DATABASE_SCHEMA.md` (Reporting), `DATA_MODEL.md` (`reportOutcome`) |
| ~~7 — Polish and fold-in~~ | `79969fe` + this | all five entries above |

**The one thing this plan asked for that was never verified**: the live
two-person confirm/dispute flow. The rules are evaluated against two distinct
authenticated leaders in `firestore-tests/results.test.mjs` and the derivation is
covered in `SeasonGameTests`, but no two real accounts have ever reported a
result to each other. Recorded in `GAPS.md`; do not read "shipped" as "verified
end to end".

## 7. Explicitly out of reach for v1

Named so nobody spends a day discovering them.

- **Server-side matchmaking and real push notifications.** Both need Blaze +
  Cloud Functions. §0.1 and §4.
- **Tamper-proof results.** Mutual confirmation is the ceiling without a
  server. §3.
- **Skill rating (Elo / TrueSkill).** A natural Phase 8 once there is a corpus
  of confirmed games — and note the record-proximity soft rule is already the
  hook where a rating would plug in.
- **Cross-region matchmaking.** Blocked on `SCALE_UP.md` S1.1's real region
  key.
- **Formats other than 3v3.** The schema carries `format` from day one so
  adding 1v1 and 5v5 is an allowlist entry and a roster bound, not a migration.
- **Standings / leaderboards.** Needs the derived record to be cheap at scale,
  i.e. the counter cache §1.1 deliberately defers.
- **Kicking a member mid-season, and leader transfer.** The rules can express
  both (a leader-only single-uid removal); they are a Phase 2.5 if squads
  churn, not a launch requirement.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| **Empty pool.** A new city has one squad. Queueing forever is the default experience, not the edge case. | Relaxation (§2.1) plus an honest UI. Consider seeding: let a squad post an *open challenge* visible on Squad home, which is a one-sided ticket anyone can accept — cheaper than matchmaking and better when the pool is two. |
| **Claim contention at launch scale.** | §2.5. Low real risk. |
| Stale claim wedges a ticket. | 90s expiry enforced in three places (§2.3). |
| A leader disbands a squad mid-season. | Names denormalized onto `seasonGames` (§1.5), so history survives. |
| Result disputes with no arbiter. | Disputed games count for nobody, and re-reporting is allowed. Accepted, documented. |
| Court dataset is six Triangle cities. | Same coverage limit `GAPS.md` already records for the map. Seasons makes it more visible, not worse. |
| A fourth tab crowds the bar. | §5, checked at large Dynamic Type before the label is fixed. |
| Rules complexity — `get()` in a hot write path. | Two accesses per write, well under the ceiling; parity tests extended in Phase 1. |
