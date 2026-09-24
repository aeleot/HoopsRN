# Plan — Enhancement Backlog

**Status:** proposed — every story below is unbuilt
**Drafted:** 2026-08-21 · **Pruned:** 2026-09-24 (shipped stories removed —
they're in git history and the dictionary entries)
**Touches:** each story names its own files

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a story below ships, fold what's true into the entries it
> names and **delete the story** from here.

Medium-to-large stories across four tracks: a solo **Queue Up**, **Friends**,
**UI** depth, and one **Blaze-gated** correctness story. `plans/SCALE_UP.md`
sequences multi-city scaling; this is the layer beneath it.

---

## Track A — Queue Up (solo)

**The goal:** a player who wants to hoop right now taps one button and ends up
in a run with nearby players, without scheduling anything or knowing anybody.
Squads already have this in Seasons (`matchTickets`); this is the same idea for
one player and the `games` collection.

### The constraint that shapes the whole design

There are no Cloud Functions (Spark plan), so **there is no server-side
matchmaker.** Nothing can wake up, look at a pool of waiting players, and
assign them to a game. Any design that assumes a matchmaking process exists is
designing for a plan this project isn't on.

The `games` update rule is what makes a client-side answer possible anyway:

```
members(incoming()).difference(members(resource.data)).hasOnly([request.auth.uid])
```

A caller may add or remove **themselves** from a roster, and nobody else. So
matching cannot be *push* (someone assigns you to a game) but it can be
**pull**: a run is created by one player, and every other interested player's
client joins it *itself*, with the write the rules already permit. Nobody ever
writes another person's uid, so **Track A needs no change to the `games` rules
at all.**

That inverts the usual matchmaking shape and it's worth stating plainly before
anyone writes code, because the obvious design — "the queue assigns you to a
game" — is precisely the one the rules forbid.

---

### A1 — Instant match: find-or-create a run at a nearby court

**Size:** Large

The first and most important insight about this feature: **most of it needs no
new collection.** A "Queue Up" button that finds the best open public run near
you and joins it — creating one only if nothing fits — delivers the core value
using the `games` collection exactly as it exists, with no new schema, no new
rules, and no new listener.

Ship this before building a queue, because it's also the thing that determines
whether a queue is needed: if there's usually something to join, the waiting
state is a rare fallback rather than the main experience.

*Flow:*
1. Player taps **Queue Up**, optionally narrowing by court or time window
   ("now", "within an hour", "tonight").
2. The client ranks already-visible public runs — it already holds them, via
   `GameService.publicGames` — by fit: has space, starts inside the window, is
   within `preferredRadius` of `LocationService.homeLocation`, and has friends
   on it (the friends-here count `LocalRunsViewModel` already computes).
3. Best fit → join it, using the existing self-join write.
4. Nothing fits → create a public run at the nearest sensible court with a
   default roster size, which then becomes the thing the *next* player's Queue
   Up finds.

*Acceptance criteria:*
- One primary action reaches a joined run in a single tap when a fit exists,
  and in one tap plus a confirm when a run has to be created.
- Ranking is a **pure, testable function** over `[Game]` + anchor + window +
  radius, in the `Game.isVisible(at:)` / `FindAMatchViewModel.nearby(courts:to:)`
  tradition — no Firestore needed to test it, and it gets real unit coverage as
  part of this story rather than joining the untested pile.
- Creating a run from Queue Up produces a document indistinguishable from one
  `CreateGameSheet` produces — same validation, same derived `status`, same
  pinned timestamps. No second write path into `games`.
- The "nothing to join, want to start one?" state is designed, not an error —
  it is the expected outcome in a new city and should read as an invitation.
- Only one write in flight, matching the existing `pendingGameId` convention on
  Local Runs.

*Risk to name up front:* this makes it much easier to create runs, so it can
produce a scatter of one-player runs at nearby courts rather than one run with
six players. Mitigate by biasing creation hard toward **courts that already
have runs or check-ins**, and by preferring to join a run up to ~20 minutes
outside the requested window before creating a competing one. Worth watching
after launch as the feature's main failure mode.

---

### A2 — The queue proper: advertised intent with a live count

**Size:** Large · **Depends on:** A1

For when A1 finds nothing: instead of creating a run that sits empty, the
player joins a **queue** — an advertised intent to play, visible to other
nearby players, that turns into a run once enough people want the same thing.

*Schema — `queueEntries/{uid}`:*

| field | type | notes |
|---|---|---|
| `userId` | string | Duplicates the document ID, per house convention. |
| `courtId` | string? | A specific court, or absent for "anywhere nearby". |
| `region` | string | The `SCALE_UP.md` S1.1 region key — what the query filters on. |
| `windowStart` / `windowEnd` | timestamp | When they're available. Bounded server-side. |
| `createdAt` | timestamp | Pinned to `request.time`. |
| `expiresAt` | timestamp | Client-supplied, rules-bounded, queried against. |

**Document ID is the uid**, which structurally enforces one queue entry per
person — the same trick `checkins/{uid}` uses in `plans/LIVE_HEADCOUNT.md`, and
for the same reason: no duplicate-entry logic to write because there's nowhere
to put a second row.

> ### Architectural decision this story must settle first
>
> **`queueEntries/{uid}` and `checkins/{uid}` are nearly the same collection.**
> Both are one ephemeral, publicly-readable document per user, pinned to a
> court, with a server-pinned creation time and a rules-bounded expiry. Building
> them as two separate collections means two services, two rules blocks, two
> indexes, two expiry regimes, and two answers to "is this person available."
>
> The alternative is one `presence/{uid}` collection with an `intent` field
> (`atCourt` / `wantsToPlay`), where headcount is `intent == atCourt` and the
> queue is `intent == wantsToPlay`. Same query shape, one schema.
>
> **This is a decision, not a detail, and it has to be made before either
> ships** — `plans/LIVE_HEADCOUNT.md` is still unbuilt, so the cheap moment to
> unify is now. Whichever way it goes, record it in
> `database/DATABASE_SCHEMA.md` with the reasoning, and update
> `plans/LIVE_HEADCOUNT.md` to match.
>
> **Partly resolved by Seasons, 2026-08-29.** A third ephemeral collection has
> since shipped — `matchTickets`, a squad's standing offer to play — and it is
> deliberately **not** part of this unification. `database/DATABASE_SCHEMA.md`'s `matchTickets` section records the
> reasoning: its subject is a squad rather than a person, its lifecycle is a
> two-party negotiation rather than a self-declaration, and its ID space is
> squad IDs. Folding a squad ticket into a per-user presence document would put
> two different subjects in one collection to save a rules block.
>
> **The decision above is still open**, and still this story's to make: it is
> about `queueEntries/{uid}` and `checkins/{uid}`, both of which are per-person
> and both of which are still unbuilt. `matchTickets` is simply not a third
> candidate, and is named here so nobody has to wonder whether it was forgotten.

*Acceptance criteria:*
- The decision above is recorded in the schema doc before implementation
  starts.
- Rules follow the `checkins` block already drafted in
  `plans/LIVE_HEADCOUNT.md` §4: owner-only write, `createdAt == request.time`,
  `expiresAt` bounded (recommend 2h default / 3h ceiling, matching that plan so
  two ephemeral collections don't disagree about what "stale" means),
  delete allowed as the check-out equivalent.
- Composite index on `(region ASC, expiresAt ASC)`, plus `(courtId ASC,
  expiresAt ASC)` for the per-court count. Deployed **before** the client that
  queries them ships.
- **The `expiresAt > now` filter is mandatory on every read.** Firestore TTL
  deletion lags well past the expiry instant, so a stale document is normal and
  any count that skips the filter over-reports. This is stated in
  `LIVE_HEADCOUNT.md` §3 and applies here identically.
- The queue view shows a live count ("4 players waiting near you") and the
  user's own state, and leaving the queue is a one-tap delete.
- Sign-out clears the entry.

---

### A3 — Auto-form: turn a full queue into a run without a server

**Size:** Large · **Depends on:** A2

When enough players are queued for the same court and window, a run should
appear for all of them without anyone having to act. With no Cloud Function,
one of the *clients* has to create it — which means the clients must agree on
**which one**, without talking to each other.

*The mechanism:* deterministic leader election on data every client already
has. All queued clients see the same filtered `queueEntries` set; the entry
with the **lowest uid** is the leader; that client alone creates the `Game`.
Every other queued client sees the new run on its existing public-games
listener and **self-joins** — the write the `games` rules already permit — then
deletes its own queue entry.

No coordination, no server, no new rules on `games`. Firebase uids are ASCII
alphanumeric, so every client's `<` agrees — the same property
`friendships`' `{uidA}_{uidB}` ordering already relies on.

*Acceptance criteria:*
- Leader selection is a **pure static function** over the queue set, unit
  tested directly — including the cases that matter: single entry, ties broken
  deterministically, and the leader's own entry having expired.
- A settle delay (recommend 2–5s) before the leader writes, so clients whose
  snapshots landed a moment apart converge on the same set first.
- **The duplicate-run race is handled, not assumed away.** Two clients can
  briefly disagree about the set and both create a run. The rules cannot
  prevent this — nothing makes a `games` create conditional on another
  document. Mitigations, in order: the settle delay; non-leaders never create;
  and a client that finds *two* matching fresh runs for its queue window joins
  the earlier-created one and shows the other normally rather than treating it
  as an error. Duplicate runs are a UX cost, not a data-integrity failure —
  say so in the docs rather than implying the design prevents them.
- Threshold is configurable and defaults to something a court can actually use
  (4 for a 2v2 is the recommended starting point, not 10).
- A player whose run was auto-formed gets an unmistakable in-app state change —
  they cannot be *notified*, because push needs Cloud Functions
  (`SCALE_UP.md` §5). **This is the feature's biggest honest limitation:** a
  player who backgrounds the app will not learn their run formed until they
  reopen it. Design the queue as a foreground activity ("stay on this screen"),
  and note push as the thing that fixes it properly whenever Blaze is
  revisited.
- Queue entries are deleted on successful join; a failed join leaves the entry
  intact so the next cycle retries.

*Recommendation:* ship A1 and A2 and **watch real usage before building A3.**
If A1's find-or-create is landing people in runs, auto-forming is a refinement;
if it isn't, A3 is the fix. Building it speculatively risks a lot of
distributed-systems machinery for a problem A1 may have already solved.

---

## Track B — Friends

### B1 — Make `@handle` mean something (or stop showing it)

**Size:** Large

`ProfileView` renders the display name as `@handle`, `FriendRow`'s subtitle is
"**always the handle**," and `UI_SHELL.md` explains the subtitle choice by
saying the handle "is what distinguishes two friends who share a display name."

**It isn't.** `userName` is explicitly a non-unique display name — nothing in
the client or the rules enforces uniqueness (`DATA_MODEL.md`, and the rules
only bound it to 1–50 characters). So two users can both render as `@mike`, and
the one piece of UI presented as the disambiguator doesn't disambiguate. The
`@` sigil is a promise the schema doesn't keep, and it gets more wrong with
every user added.

`database/DATABASE_SCHEMA.md` already lists "a separate unique `username`
handle" under *Deliberately excluded from v1*. This story is the decision to
either include it or drop the pretense.

*Option 1 — real handles (recommended if the social side is a priority):* a
`handles/{handleLower}` collection whose document ID **is** the handle, holding
only `{ uid }`. Uniqueness comes free from Firestore document IDs — a create
against an existing ID fails, no transaction or Function needed. This is the
same "derive the ID from the content so only one document can exist" trick
`friendships/{uidA}_{uidB}` already uses, and it works on Spark.

*Option 2 — drop the sigil:* render the display name plainly, and use the
existing copyable **Player ID** row as the real disambiguator. Cheap, honest,
and loses nothing functional.

*Acceptance criteria:*
- A decision is recorded in `DATA_MODEL.md` and `database/DATABASE_SCHEMA.md`
  with its reasoning.
- If handles: reservation is atomic via document-ID uniqueness; claiming a
  taken handle fails with a clear message; changing a handle releases the old
  one; existing accounts get a migration path *and* a grace period in which
  they're findable by both.
- If dropping: every `@`-prefixed rendering is removed — `ProfileView`'s
  header, `FriendRow`'s subtitle, `PlayerProfileSheet` — and `UI_SHELL.md`'s
  subtitle rationale is rewritten, since its stated justification no longer
  holds either way.
- Search behavior is unchanged or better; `FriendsViewModelTests`' `merged`
  and `looksLikeUserId` cases still pass.

---

### B3 — Abuse containment: blocking, and the limits of a client-side guard

**Size:** Medium-Large

`GAPS.md`: "**No blocking, reporting, or rate limiting on friend requests.**
Anyone signed in can search for anyone and send them a request; declining
(which deletes the edge) is the only recourse, and nothing stops the same
person asking again."

That's a real problem at any scale and a worse one as the user base grows,
which is why it's here rather than deferred with the rest of the Friends
safety work (below).

*What is buildable on Spark:* a **block list** in the owner-only
`users/{uid}/private/…` subcollection that `SCALE_UP.md` S6.1 introduces (this
story should ship after or alongside it, sharing that migration). A blocking
user's own client filters blocked accounts out of search results, hides their
requests, and refuses to send.

*What is not:* a genuine server-side rate limit. `GAPS.md` is right that this
needs Cloud Functions. A modified client is bound by none of the client-side
guards.

*Acceptance criteria:*
- Blocking is reachable from `PlayerProfileSheet` and from an incoming request,
  behind a confirmation, and is reversible.
- A blocked account disappears from search results, its pending edges are
  deleted, and new requests from it are not surfaced.
- A per-recipient cooldown on repeat requests, enforced client-side in the same
  spirit as the existing 300ms debounce and one-write-in-flight guard.
- **The documentation says plainly what this does and does not stop.** A block
  that a modified client can bypass, described as if it were enforced, is worse
  than no block — `GAPS.md` gets an entry stating the client-side boundary and
  naming the Function that would close it.
- Reporting is explicitly out of scope (it needs somewhere for reports to *go*)
  and recorded as such rather than half-built.

*Deferred alongside it, each needing a Cloud Function or a real search index:*
push notifications on a friend request or acceptance; unique handles and
typo-tolerant search (B1 is the first half of that); mutual-friend counts; and
friends' **private** runs, which needs a real authorization design and should be
settled with C6's invite decision rather than separately.

---

## Track C — UI

### C1 — A run detail screen

**Size:** Large

`GAPS.md`: "Game cards show court, time, roster, distance and capacity only.
Player names, avatars, and any per-run detail screen are unbuilt." `GameCard`
renders capacity as a fraction (`playerIds.count / maxPlayers`) and never shows
who those players are.

This is the biggest missing surface in the app. A run is a social object and
currently reads as a number out of a number — you cannot see who you'd be
playing with before joining, which is the single most useful thing to know.

It's also a prerequisite for Track A feeling trustworthy: being auto-joined to
a run with anonymous strangers is a worse experience than being joined to a run
you can look at.

*Acceptance criteria:*
- Tapping a `GameCard` opens a detail view: court (with the map context
  `MapTab` already has), time, host, the confirmed roster, and the waitlist.
- Roster names and avatars resolve through `UserProfileService.profiles(for:)`,
  reusing `PlayerAvatar` and `FriendRow` rather than inventing a third player
  row.
- **The privacy decision is made explicitly, not by default.** `GAPS.md` notes
  names "would need a read across `users` and a privacy decision, not just a
  UI." `users` is world-readable to signed-in accounts, so this is a *display*
  choice — follow the `PlayerProfileSheet` precedent (name, avatar, home court;
  not favorites, not radius) and record it in `UI_SHELL.md`'s "anything showing
  another player" invariant.
- Every roster action available on the card is available here, resolved once
  per the existing "resolve the action once, reuse it for button and dialog"
  invariant.
- Presentation follows the shell's rules: this is not a fourth top-level
  destination, and `RootViewModel.destination` gains no case.
- Host-only controls (cancel, and the `InviteLinkCard` for a private run) are
  here too, so the card can eventually shed them.

---

### C2 — `school` courts read as public

**Size:** Small

`access` is only surfaced for `restricted`; `school` courts render as ordinary
public ones, which is misleading for a court you may not be able to use during
school hours. (The rest of this story — directions, the ODbL notice — shipped.)

*Acceptance criteria:*
- `school` access is visually distinguished with an honest caveat in
  `CourtBadges`, not silently equated to public, and `CourtBadgesTests` pins it.

---

### C3 — Empty states, first-run, and the cold-start problem

**Size:** Medium-Large

Every plan in this repo names cold start as its main risk —
`plans/LIVE_HEADCOUNT.md` says it outright ("Nobody checks in when the count
always reads zero... a product risk to plan around, not something the schema
fixes"), and `SCALE_UP.md` §1 shows a new city's users can see an empty list
even when the app is working correctly. Track A makes it sharper: a queue with
nobody in it is the default state in a new market.

This story treats the empty state as a designed surface rather than the absence
of one.

**The screens' own empty states are designed now** — the UI revamp gave Home,
Runs, Seasons and the inbox each a composed empty state with its next action.
What's left is the Track A queue's (once it exists) and first-run onboarding.

*Acceptance criteria:*
- The Track A queue's empty state says what's happening and offers the next
  action. `LIVE_HEADCOUNT.md` already models the tone: "No one here yet" over
  "0 players."
- First-run onboarding covers the three things that make the app work: location
  permission (with the reason), home region/city
  (`SCALE_UP.md` S2.2), and a display name.
- The distinction between "nothing here" and "we couldn't load it" is never
  ambiguous — the existing `ErrorBanner` + `isRecovering` treatment stays for
  the second, and empty states never impersonate it.
- A brand-new account with no friends and no runs nearby has a coherent path
  forward on every screen, not four blank panels.

---

### C6 — Invite links: build the receiving half

**Size:** Large

Sending shipped 2026-08-15 — `Support/InviteLink.swift` mints a
`hoopsrn://game/{id}` string, `CreateGameSheet` shows it after a private run
is created, and `GameCard`/`InviteLinkCard` repeat it for a host. None of it
does anything yet: `hoopsrn` isn't registered under `CFBundleURLSchemes`,
nothing implements `.onOpenURL` in `hooprApp.swift`, and the `games` `read`
rule refuses a non-member exactly as it should for a run with `isPublic ==
false` — so a recipient who taps the link today gets nothing. `gaps/GAMES.md`
has the full worked shape; this story is building it.

*The decision this story has to make, not default into:* the current `read`
rule is one clause covering both the list query and a direct-by-ID get. An
unguessable document ID is not, by itself, an authorization model — anyone who
learns the ID (a forwarded link, a leaked log line) can attempt the same read.
Two ways to close that honestly:

- *Option 1 — trust the ID (simplest):* leave the rule as-is; a private run's
  ID is the only credential, generated server-side and never enumerable.
  Cheap, and consistent with how `friendships/{uidA}_{uidB}` already treats a
  derived ID as sufficient. Weakest if a link is ever pasted somewhere public.
- *Option 2 — an `inviteToken` field, checked separately from membership:* a
  rotatable credential distinct from the document ID, checked in the read
  rule. Real revocation (a host can invalidate a leaked link without deleting
  the run), at the cost of a schema field, a rule clause, and a "regenerate
  invite" affordance somewhere.

`context/gaps/GAMES.md` carries the load-bearing decision — the `get`/`list`
split versus an `inviteToken`. 

*Acceptance criteria:*
- The decision above is recorded in `database/DATABASE_SCHEMA.md` with its
  reasoning.
- `hoopsrn` registered under `CFBundleURLSchemes`; `hooprApp.swift` handles
  `.onOpenURL`, stashing the pending `gameId` across a cold start and a
  sign-in that hasn't completed yet.
- `GameService.fetchGame(byId:)` added alongside the existing `createGame` /
  `joinGame` / `leaveGame` / `cancelGame` methods, following the same
  error-mapping convention as the rest of the service.
- An `InviteJoinView` (or equivalent) covers every state a link can land in,
  not just the happy path: already on the roster, full (offers the
  waitlist), aged past `visibilityGrace`, deleted, and the "not signed in
  yet" case the pending-`gameId` stash exists to handle.
- Joining through an invite link uses the same self-join write `C1`'s roster
  actions and `A1`'s Queue Up use — no second join path into `games`.
- `InviteLink.swift`'s doc comment ("**The link is not yet openable**") and
  `gaps/GAMES.md` are both updated once this ships.

---

## Track D — Needs the Blaze plan

### D6 — Waitlist promotion and *automatic* run completion

**Size:** Large · **Note:** the first story in this backlog that needs the
Blaze plan

What's left: **waitlist promotion** — "the freed slot isn't handed to the
first waitlisted player; the update rule forbids writing another user's uid,
deliberately" — and **automatic completion**, finishing a run whose host never
marks it. (Host-triggered completion shipped 2026-09-18 on Spark.)
`in_progress` is still declared and never written.

The `games` update rule's membership diff is exactly as deliberate as Track
A's design note says: a caller may only move themselves across
`playerIds`/`queuedPlayerIds`, so *no client write* can hand a departing
player's seat to someone else. That's correct and shouldn't be loosened — it's
the same guarantee Track A leans on. The honest fix is server-side, which this
project has avoided everywhere else specifically to stay on Spark. This story
is the one place in the backlog to name that directly and make the call
rather than let it sit as an unstated gap forever.

*Acceptance criteria:*
- **The plan decision is made explicitly and recorded**, not defaulted into.
  If the project moves to Blaze: a Cloud Function triggered on `games`
  updates promotes the first `queuedPlayerIds` entry into `playerIds` when a
  confirmed player leaves a run that still has a waitlist, and a scheduled
  Function transitions `open`/`full` → `in_progress` at `scheduledTime` and →
  `completed` after some duration, superseding the client-side
  `visibilityGrace` hiding used today. If the project stays on Spark:
  this story stays recorded as deferred in `gaps/GAMES.md` and
  `ROADMAP.md` §0, not silently dropped.
- Promotion selection is a **pure function** over `queuedPlayerIds`
  (first-in, first-out unless a different order is chosen deliberately), unit
  tested independent of the Function runtime — the same discipline every
  other matching decision in this backlog follows.
- The Function runs with admin credentials, so it is exempt from the
  membership-diff rule by design (Cloud Functions bypass Firestore security
  rules) — state that next to the rule itself in
  `database/DATABASE_SCHEMA.md`, so a future reader doesn't conclude the rule
  was weakened.
- A promoted player gets an in-app state change; per `A3`'s honest
  limitation, they cannot be *pushed* to unless `SCALE_UP.md` §5's push
  design lands alongside this.
- The client-side `visibilityGrace` window stays as the fallback for any
  run this Function hasn't reached yet (deploy lag, a cold Function), so a
  stale run never renders as live even if the status write is late.

---

## Suggested sequencing

Not a commitment — the order with the fewest blocked dependencies:

1. **C1** (run detail) — the biggest missing surface, and a prerequisite for
   Track A feeling trustworthy.
2. **C6** (invite links) — the largest thing that needs no infrastructure
   decision; settles friends' private runs with it.
3. **A1** (instant match) — the feature at its smallest useful size.
4. **A2** (the queue) + the `presence`-vs-`checkins` decision it shares with
   `plans/LIVE_HEADCOUNT.md`.
5. **B1** / **B3** / **C2** / **C3** — parallel; none has a rules or index
   dependency on the others.
6. **A3** (auto-form) — only if A1 and A2 leave people waiting.
7. **D6** — gated on the Blaze decision in `ROADMAP.md` §0.

## See also

- `plans/SCALE_UP.md` — the multi-city scaling this backlog sits under.
- `plans/LIVE_HEADCOUNT.md` — the `checkins` design A2 must be reconciled with.
- `ROADMAP.md` — what to reach for first, across plans and gaps.
- `GAPS.md` — what's wrong with what already exists.
