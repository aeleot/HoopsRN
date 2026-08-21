# Plan — Enhancement Backlog

**Status:** proposed, not started
**Drafted:** 2026-08-21
**Touches:** everything below names its own files

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a story below ships, fold what's true into the dictionary
> entries it names and strike it from here.

Medium-to-large stories across four tracks: the **Queue Up** feature, the
**Friends** system, **UI** depth, and **correctness/standards**. Each is sized
to be a real chunk of work — a few days, not an afternoon — because the small
one-line fixes have been consolidated into the themed stories that own them
rather than listed individually.

`plans/SCALE_UP.md` sequences the multi-city scaling work. This document is the
layer beneath it: enhancements to what already exists. Where a story here is a
hard dependency of one there, it says so.

---

## Track A — Queue Up

**The goal:** a player who wants to hoop right now taps one button and ends up
in a run with nearby players, without scheduling anything or knowing anybody.

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

### Hard dependency: A0 must ship first

Every story in this track is meaningless until the app knows where the user
actually is. Today `LocationService.homeLocation` returns a hardcoded downtown
Durham coordinate for every user on Earth (`LocationService.swift:19`), and
every distance in the app measures from it. "Nearby players" computed from that
is "players near Durham," for a user in Phoenix included.

---

### A0 — Anchor the app to the device's real location

**Size:** Medium · **Blocks:** every other story in Track A, and
`SCALE_UP.md` S2.2

`LocationService.userLocation` is published and, per `GAPS.md`, consumed by
nothing. `homeLocation` is a `static var` returning `defaultLocation` — a
comment above it already names swapping it for a profile-owned value as "the
intended future change," and notes that doing it in that one place moves the
map's initial region, the nearby-courts list, the recenter target, and the
Local Runs radius filter together.

That single-seam design is the reason this is a Medium and not a Large. The
work is mostly deciding the fallback chain, not rewiring four call sites.

*Acceptance criteria:*
- `homeLocation` becomes an instance property resolved through a documented
  precedence: device location (when authorized and fresh) → the profile's
  `homeRegion`/`homeCourtId` centroid → the current Durham constant as the
  last-resort fallback. The constant stays; it stops being the only answer.
- Location permission is requested at a moment that explains itself (a "find
  courts near me" affordance), not silently on first recenter as today.
- A user who **declines** location permission still gets a usable app — the
  profile-derived fallback is what they get, and the UI says which anchor is
  in use rather than silently showing distances from somewhere else.
- Distances visibly change when the anchor changes, in all four consumers, with
  no edit outside `LocationService` and the injection chain.
- `MAP_LAYER.md`'s "Distances and location" section and its final invariant are
  updated — both currently document the hardcoded point as intended behavior.

*Open decision:* whether the anchor is *live* (follows the user as they move)
or *sticky per session*. Live is what a queue wants; sticky is cheaper and
avoids a list that reorders while being read. Recommend sticky-per-foreground:
resolve on foreground, hold for the session.

---

### A1 — Instant match: find-or-create a run at a nearby court

**Size:** Large · **Depends on:** A0

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
   within `preferredRadius` of the A0 anchor, and (once F2 ships) has friends
   on it.
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
  (`SCALE_UP.md` §7). **This is the feature's biggest honest limitation:** a
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

### B2 — Friends in context: badges on runs and the queue

**Size:** Medium-Large

`plans/FRIENDS.md` Phase 4 is the "N friends here" badge on `GameCard` — a
client-side intersection of two lists the app already holds, needing no rules,
index, or listener change. `MainTabView` already has `friendService` to pass in.

Worth extending in the same story rather than shipping the badge alone: the
same intersection is what makes Track A's queue feel social instead of
anonymous ("2 friends are waiting at Rockwood"), and it's what should bias A1's
ranking toward runs your friends are already on.

*Acceptance criteria:*
- `LocalRunsViewModel` gains `friendService`; `GameCard` shows a friends badge
  when the intersection is non-empty and nothing when it's empty.
- The intersection is a pure function with unit coverage, following the
  `FriendsViewModel` `nonisolated static` pattern that exists precisely so
  these decisions test without Firebase or a main actor.
- A1's ranking treats "a friend is on this run" as a ranking input.
- **The privacy line is drawn deliberately:** this surfaces friends on runs
  *already visible to you*. It does not make a friend's private run visible —
  that needs the authorization design `plans/FRIENDS.md` and
  `database/DATABASE_SCHEMA.md` both defer, and it stays out of scope here.
- Names resolve through the existing `UserProfileService.profiles(for:)` cache;
  an unresolved name degrades to a count, never a blank row.

---

### B3 — Abuse containment: blocking, and the limits of a client-side guard

**Size:** Medium-Large

`GAPS.md`: "**No blocking, reporting, or rate limiting on friend requests.**
Anyone signed in can search for anyone and send them a request; declining
(which deletes the edge) is the only recourse, and nothing stops the same
person asking again."

That's a real problem at any scale and a worse one as the user base grows,
which is why it's here rather than deferred to Phase 5 with the rest.

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

---

### B4 — Close out the friends verification and backfill debt

**Size:** Medium

Two known-open items from the Friends TODO in `GAPS.md`, plus its search gap:

- **`sendRequest`'s simultaneous-request collision has never run against a live
  pair.** Phase 3 made it reachable from the UI for the first time; reaching it
  needs two accounts requesting each other before either sees the other's
  request. Still not done.
- **The six-check manual rules pass "was a one-time manual pass, not
  coverage."** Nothing in the repo re-runs it. Any edit to the `friendships`
  block or the `users` allowlists is unverified until someone repeats it by
  hand.
- **`userNameLower` is missing on every pre-search account**, so those people
  are unfindable by name until their owner reopens the app. The client-side
  self-heal is the whole migration today.

*Acceptance criteria:*
- The collision path is exercised against a real pair and the result recorded —
  including confirming a genuine `permission-denied` (undeployed rules) is
  still distinguishable from the collision, since both reach the same catch.
- The `userNameLower` backfill runs as a one-off Admin SDK script — which needs
  a service account, **not** the Blaze plan — folded into the same script pass
  as `SCALE_UP.md` S1.3 rather than run separately.
- The six manual checks are converted into emulator tests as part of C4/D3
  below, or explicitly re-run and re-dated if that story hasn't landed.
- Test data is cleaned: the hand-seeded friendship between the developer's
  account and `chaseallen122` in the production project is deleted.

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

### C2 — Court detail depth and the licence obligation

**Size:** Medium-Large

The court detail card carries name, address, badges and Start Run. `CourtBadges`
(used at `MapTab.swift:488` and `CourtRow.swift:29`) already surfaces hoops,
lights, covered, surface and restricted access — so the dataset's attributes
are *partly* used. What's still missing is the depth that makes the map worth
opening, and one outright obligation:

- **The ODbL attribution is never displayed.** `CourtDataset.attribution`
  carries "Court data © OpenStreetMap contributors, ODbL 1.0" and nothing
  renders it. This is a licence term the app is currently not meeting — the one
  item in this document that is a compliance issue rather than a preference.
- `access` is only surfaced for `restricted`; `school` courts render as
  ordinary public ones, which is misleading for a court you may not be able to
  use during school hours.
- No way to get directions to a court, which is the obvious next action after
  "this one."

*Acceptance criteria:*
- Attribution is displayed somewhere durable and discoverable — the court
  detail sheet's footer, an About row on the profile, or both. Not a log line.
- `school` access is visually distinguished with an honest caveat, not silently
  equated to public.
- A "Directions" action hands off to Maps.
- Favorites and the run count at a court (once Track A exists) are visible from
  the detail card.
- `COURT_DATASET.md`'s invariant about the attribution "travelling with the
  data" is extended to say where it surfaces.

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

*Acceptance criteria:*
- Every list surface — Local Runs (both sections), Friends, search results,
  nearby courts, and the Track A queue — has a designed empty state that says
  what's happening and offers the useful next action. `LIVE_HEADCOUNT.md`
  already models the tone: "No one here yet" over "0 players."
- First-run onboarding covers the three things that make the app work: location
  permission (with the reason, per A0), home region/city
  (`SCALE_UP.md` S2.2), and a display name.
- The distinction between "nothing here" and "we couldn't load it" is never
  ambiguous — the existing `ErrorBanner` + `isRecovering` treatment stays for
  the second, and empty states never impersonate it.
- A brand-new account with no friends and no runs nearby has a coherent path
  forward on every screen, not four blank panels.

---

### C4 — Accessibility and Dynamic Type audit

**Size:** Medium

The type system is already built for this — `.hooprFont(_:weight:maximumSize:)`
scales through `UIFontMetrics`, `ProfileView`'s cards take a floor rather than a
fixed height specifically so seams stay aligned at every Dynamic Type size, and
`maximumSize` caps scaling only where a frame genuinely can't grow. The
foundation is unusually good; what's missing is verification that it holds
everywhere.

*Acceptance criteria:*
- Every screen is walked at the largest accessibility text size; anything that
  clips or overlaps is fixed by the floor-plus-stretch pattern `ProfileView`
  already establishes, not by adding a `maximumSize` cap to make the problem
  invisible.
- VoiceOver labels on every interactive control. `MapTab` already labels
  recenter, favorite and close — the map's court annotations deliberately
  populate `title` for VoiceOver while rendering no label, and that should be
  verified as actually reaching the user.
- Both appearances checked, including the map's `UIColor` marker tint, whose
  documented failure mode (a colour frozen at whichever appearance was current
  when it was assigned to a `CALayer`) is exactly the bug that hides until
  someone toggles dark mode mid-session.
- Contrast ratios verified for `hooprSecondaryText` on `hooprSurface` and for
  `hooprOnBrand` on both orange values.
- **Scope note:** this is iPhone-portrait only. The build declares iPad and
  Vision support (`SUPPORTED_PLATFORMS`, device family `1,2,7`) while the UI is
  iPhone-shaped throughout. Either narrow the declaration or open a separate
  story for real adaptive layout — don't let this one quietly become that.

---

## Track D — Correctness and standards

### D1 — Repair the context dictionary

**Size:** Medium

The context library is the reason this codebase can be picked up cold, and it
has drifted. `GAPS.md` is supposed to be where drift is recorded — it has
itself drifted, which is the worst place for it to happen, because it's the
entry every other entry tells you to read before trusting a comment.

**Verified against the source on 2026-08-21:**

| Where | Says | Actually |
|---|---|---|
| `GAPS.md` §7 | "Fix `RootViewModel`'s retain cycle to match the other two view models" | Already fixed. `RootViewModel.swift:28-34` uses `sink { [weak self] }` with a comment explaining why. All four view models now do. |
| `GAPS.md` §7 | "Replace `UIScreen.main.bounds` in `MapTab`; it's the only deprecation warning in the build" | Already fixed. `MapTab.swift:59-63` uses `onGeometryChange`-fed `containerHeight`, seeded at 852, with a comment saying it avoids the deprecated API. No `UIScreen.main` call remains anywhere. |
| `GAPS.md` (Assets and data) | "`courts_updated.json` … is committed and bundled but never loaded" | Not present. `Resources/` contains only `courts.json`. |
| `GAPS.md` (Unfinished) | `hoops`, `surface`, `isLit`, `isCovered`, `access` "are read **nowhere** except the filter chips" | `CourtBadges.swift` renders all five, used by `CourtRow.swift:29` and the court detail card at `MapTab.swift:488`. |
| `ARCHITECTURE.md` (ownership table) | `CourtService` publishes `courts: [Court]`, `loadError: String?` | No `loadError` exists anywhere in the Swift sources. `CourtService` publishes `courts` only and logs failures. |
| `COURT_DATASET.md` | A load failure "publishes `loadError = "Court data unavailable"`" | Same — it logs and leaves `courts` empty. The doc describes UI that was never built. |
| `DATA_MODEL.md` (`CourtDataset`) | "`CourtService` reads `version` and `attribution` into stored properties" | It reads `version` inline for a log line and never stores it; `attribution` is never read at all. |
| `MAP_LAYER.md` | Sheet state is `.list` / `.collapsed` / `.detail(court:returningTo: RestState)`; "Sheet height is `UIScreen.main.bounds.height / 3`" | `MapTab.swift:7-33` has a three-case `Detent` (`collapsed`/`medium`/`expanded`) and `SheetState` of `.rest(Detent)` / `.detail(court:returningTo: Detent)`. Heights are fractions of `containerHeight`. |

*Acceptance criteria:*
- Every row above is either corrected in the owning entry or, if it's a real
  gap, restated accurately.
- The `attribution` row is **not** simply deleted — it's a live licence
  obligation (C2). Correcting the doc must not lose the obligation.
- `Verified` stamps are re-dated on every entry touched.
- `context/prompts/refresh-context-dictionary.md` is run, and if it did not
  catch these, the prompt is improved — a drift-detection process that misses
  four stale claims in one entry needs adjusting, not just re-running.

---

### D2 — Unit-test the untested decisions

**Size:** Large

`GAPS.md` names what's worth testing and untested. The pattern to follow already
exists and is good: `FriendsViewModel`'s three helpers are `nonisolated static`
*precisely* so they test without Firebase, a live service, or a main actor.
Most items below are already pure or one refactor away.

*Acceptance criteria (each gets real coverage):*
- `RootViewModel`'s gating rule — the reason the type exists separately from
  `RootView`.
- `FindAMatchViewModel.nearby(courts:to:)` filtering and ordering, including
  the `preferredRadius` edge case `DATA_MODEL.md` warns about: a stored `0`
  read directly instead of through `validRadius` silently empties the list.
- `LocalRunsViewModel.action(for:)` and its radius/dedupe filtering — the
  function whose correctness the "resolve once, reuse for button and dialog"
  invariant depends on.
- All four services' `mapped(_:)` error translations, including
  `AuthError.notConfigured`'s string-match-before-code path, which is fragile
  by necessity and untested.
- `FriendsViewModel`'s profile-resolution cache, including the
  name-that-never-resolves case.
- Track A's ranking (A1) and leader election (A3) land with tests as part of
  those stories, not here.
- **Also fix the UI test target**, which fails to launch its runner
  (`RequestDenied` from SpringBoard), forcing every `xcodebuild test` to be
  scoped with `-only-testing:hooprTests`. A test target that can't run is worse
  than none, because it makes the working suite awkward to invoke.

---

### D3 — Rules coverage via the Firebase emulator

**Size:** Large

The rules carry the project's most consequential logic — the membership diff,
pinned server timestamps, derived status, duplicate-roster guards, the
friendship's asymmetric authority — and **none of it has automated coverage.**
`FirestoreRulesParityTests` pins shared *constants* and is explicit about not
being a rules evaluator.

`firebase emulators:exec` with `@firebase/rules-unit-testing` runs locally and
needs no billing change. It needs a Node test target rather than a Swift one.

This is listed twice in `GAPS.md` (items 2 and 6) and in `SCALE_UP.md` §5,
which is a fair signal of how overdue it is. Every story above that touches
rules — A2's `queueEntries`, B1's `handles`, B3's block list, `SCALE_UP.md`'s
`region` and `private` subcollection — adds a clause that nothing will verify
until this exists.

*Acceptance criteria:*
- Emulator setup committed and documented in `BUILD_AND_CONFIG.md`, runnable in
  one command.
- `games` covered: a non-member can't read a private run; the membership diff
  rejects writing another uid; duplicate rosters are rejected; the host can't
  leave; rosters stay disjoint; only the host deletes.
- `friendships` covered: the six checks from the 2026-08-14 manual pass become
  automated, closing B4's "one-time pass, not coverage."
- `users` covered: the create and update key allowlists, and that a
  non-owner cannot write.
- The suite runs in CI, or — if there's no CI yet — the story includes standing
  it up, because a local-only suite is one people forget to run.

---

### D4 — Retire finished runs on a schedule the client can trust

**Size:** Medium

`SCALE_UP.md` §1 fixes *which* runs are queried; this fixes *when* they stop
being queried. `GAPS.md` step 1 describes it: `Game.visibilityGrace` is 3h, and
the query's cutoff is **fixed when the listener attaches**. A session left open
overnight keeps querying against last night's cutoff. `isVisible(at:)` hides
those rows client-side so nothing wrong is displayed, but the query keeps paying
for them and spends its `limit(to:)` budget on runs that will never render.

`attachListeners()` recomputes the cutoff per attach, but only runs on sign-in
and on recovery — a healthy long-lived session holds its original cutoff
indefinitely.

*Acceptance criteria:*
- The cutoff is recomputed and the listeners re-attached on foreground, via
  `scenePhase` — the cheapest of the three options `GAPS.md` lists, and the one
  that doesn't remove an index or need a Cloud Function.
- Re-attach reuses the existing `ListenerSupervisor` path rather than adding a
  second way to attach, and every new snapshot still reports success/failure by
  listener key — a listener that skips this is one that never comes back.
- The grace window is confirmed as a deliberate value (6h was floated) and, if
  changed, changed in `Models/Game.swift` where both consumers read it.
- The `in_progress` / `completed` statuses stay unwritten and that stays
  documented — moving retirement server-side needs a scheduled Function
  (`SCALE_UP.md` §7). This story makes the client-side window honest, not
  authoritative.

---

### C5 — Heat-colored court markers by today's scheduled game count

**Size:** Medium-Large

Every court pin reads identically today regardless of activity —
`CourtMarkerView.configureAsCourt` sets the disc to `hooprOrange`
(`hooprDarkOrange` if selected), full stop (`MapView.swift:115`), and
`configureAsCluster` always uses `hooprDarkOrange` (`MapView.swift:132`). A
court with eight runs scheduled today and one with none look the same until
the sheet is opened. This story turns the disc into a heatmap of that day's
scheduled activity, so the map itself answers "where's it happening today"
at a glance — the thing `plans/LIVE_HEADCOUNT.md` §1 identifies as missing
("the map stops being a static directory... only once headcounts exist"),
delivered here from data the app **already has**, before that plan's new
`checkins` collection exists at all.

**The good news: this needs no new collection, query, index, or rule.**
`GameService.publicGames` is already a live, session-scoped listener over
public runs (`GameService.swift:174-179`); every court a pin represents has
a stable `Court.id` every `Game.courtId` already references. The whole
feature is a client-side grouping of data already in memory — the same move
`LocalRunsViewModel` makes joining runs to the bundled court dataset, and
the reason `plans/LIVE_HEADCOUNT.md` §5 insists on "listen to documents,
don't use `count()`": the documents are already in hand, so counting them is
free.

*Design decisions this story has to settle, not default into:*

- **"Today" is a pure, testable boundary function**, not an inline date
  comparison — `startOfDay`/`endOfDay` against the device's calendar,
  mirroring how `Game.isVisible(at:)` and `Game.visibilityGrace` are kept as
  pure functions on the model specifically so they're testable without
  Firestore. Get the midnight-boundary and timezone cases into a unit test
  from the start.
- **Counting is derived, not queried.** Group `GameService.publicGames` by
  `courtId`, filter to today's window, and count — recomputed only when
  `courtService.$courts` or `gameService.$publicGames` emits, via the same
  `CombineLatest`-computed-once discipline `MAP_LAYER.md` documents for
  `NearbyCourt` ("computed once when the list is built... never during
  scroll"). Never a query keyed on `courtId` per visible pin — that's the
  per-court fan-out `plans/LIVE_HEADCOUNT.md` §6 Phase 3 explicitly warns off
  ("not one listener per court and not a query over all 213").
- **New Theme.swift roles, not a reused one.** `hooprRed` is already the
  app's error/destructive color (Sign Out, Remove home court) — routing "lots
  of games here" through it would tell a user something is wrong. Add a
  small ordered ramp (recommend three or four steps: none / light / busy /
  packed) as named roles next to the existing brand colors, each a
  light/dark pair through `Color.hoopr(light:dark:)` like every other role,
  never a literal RGB in `MapView.swift`.
- **Bucket thresholds are a stated table**, not a formula improvised at the
  call site — e.g. 0 → neutral, 1–2 → light, 3–5 → busy, 6+ → packed. Tune
  against real data once available; the point is that the boundaries live in
  one named place, the way `Game.maxPlayersRange` and `visibilityGrace` do.
- **Cluster color needs its own policy, stated plainly.** A cluster today is
  always `hooprDarkOrange` regardless of what it contains. Recommend the
  cluster shows the **hottest bucket among its members** — a cluster
  containing one packed court should read as packed, not hide it behind an
  average. Whatever is chosen, document it here and in `MAP_LAYER.md`; "the
  cluster averages/maxes/ignores member heat" is a real behavior difference
  someone will otherwise have to reverse-engineer from the diff.
- **Selection and heat both want the disc color**, and only one can have it.
  Recommend heat owns the disc's fill unconditionally, and selection keeps
  communicating through the existing scale-up transform and
  `displayPriority`/`zPriority` bump rather than also swapping color — those
  are already sufficient to mark a selected pin (per `MapView.swift:122-126`)
  without needing `hooprDarkOrange` to double as "selected." Document
  whichever way this goes in the `configureAsCourt` doc comment, since the
  current comment ("Selected pins outrank their neighbours...") doesn't
  anticipate a second color signal competing for the same property.
- **Color is never the only signal.** A colorblind user or anyone glancing
  at a small disc shouldn't need to distinguish four hues correctly.
  `CourtRow` and the court detail sheet (`C2`) should show the same count as
  a number — "6 runs scheduled today" — so the map's color is a preview of
  something stated in text elsewhere, not the only place the information
  exists. This is exactly the color-is-not-the-only-encoding rule `C4`'s
  accessibility audit exists to catch; landing it correctly here means C4
  doesn't have to find it later.

*Acceptance criteria:*
- A pure function mapping `[Game]` + `courtId` + "today" → a count, unit
  tested independently of Firestore, MapKit, or a view model — including a
  game scheduled just before midnight and one just after.
- A pure function mapping count → bucket, unit tested at every boundary
  (the off-by-one the roster-status parity tests already guard against
  elsewhere in this codebase is exactly the class of bug to watch for here).
- `FindAMatchViewModel` gains `gameService` as a dependency and publishes a
  `courtHeat: [String: Bucket]` (or similar), recomputed via `CombineLatest`
  over courts and public games — not recomputed per render, per pin, or
  during a map pan.
- **Injection chain updated**: `MainTabView` → `MapTab` →
  `FindAMatchViewModel` currently takes `courtService` + `locationService` +
  `userProfileService` + `recentCourtsStore`, no `gameService`
  (`ViewModels/FindAMatchViewModel.swift:86-96`). `plans/LIVE_HEADCOUNT.md`
  §5 already flags that its own `CheckInService` needs the same chain
  extended — **do both init-signature threadings in one pass** if the two
  stories land near each other, exactly as that plan recommends for its own
  overlapping case.
- `CourtMarkerView.configureAsCourt` takes a bucket and sets `disc
  .backgroundColor` from the new Theme roles — as a `UIView.backgroundColor`,
  never `CALayer.backgroundColor`, matching the file's existing, deliberate
  convention (`MapView.swift:41-45`) so the color re-resolves on a light/dark
  trait change instead of freezing.
- `configureAsCluster` implements the stated aggregation policy.
- Colors update **live** as `publicGames` delivers new snapshots — a run
  booked at a court while the map is open shifts that pin's bucket without a
  refresh, reusing the listener that's already open.
- A legend or one-time explainer exists somewhere reachable (the list
  header is the cheapest option) — an unlabeled color-coded map is a
  guessing game the first time someone sees it.

*Correctness dependency worth naming, not a blocker today:* counts are
derived from `GameService.publicGames`, which today has no city/region
filter and is capped at `Limit.published` (100) — `SCALE_UP.md` §1's exact
concern. At the current single-metro scale every relevant game is in that
list. Once `SCALE_UP.md` S1.2 ships (querying by `region`), this feature's
counts get *more* correct, not less — a busy local court currently at risk
of being crowded out of the global top-100 by another city's earlier-tipping
runs would undercount today. No action needed now; just don't be surprised
if heat readings look off in a second city before S1.2 lands.

*Explicitly a different signal from `plans/LIVE_HEADCOUNT.md`:* this is
**"how much is scheduled here today"**; that plan is **"how many people are
actually here right now."** They're complementary, not duplicates — a court
can be scheduled solid and empty at check-in time, or unscheduled and full
of pickup players who never opened the app. Don't merge the two encodings
into one color scale without a deliberate design pass; note the relationship
in both docs and leave them as two signals for now.

---

## Suggested sequencing

Not a commitment, just the order with the fewest blocked dependencies:

1. **A0** (real location) — blocks all of Track A and half of `SCALE_UP.md`.
2. **D1** (dictionary repair) — cheap, and every story below reads these docs.
3. **C1** (run detail) + **B2** (friend badges) — the two that make runs feel
   social, and both are prerequisites for Track A being trustworthy.
4. **A1** (instant match) — the feature, at its smallest useful size.
5. **D3** (rules coverage) — before A2/B1/B3 each add an unverified rules block.
6. **A2** (the queue) + the `presence`-vs-`checkins` decision.
7. **B1** (handles) / **B3** (blocking) / **C2** / **C3** / **C5** (heat
   markers) — parallel tracks. C5 has no rules/index dependency, so it can
   slot in wherever there's capacity rather than waiting its turn.
8. **A3** (auto-form), **D2**, **D4**, **C4** — as capacity allows.

## Documentation debt

| Entry | Change |
|---|---|
| `database/DATABASE_SCHEMA.md` | `queueEntries` (or `presence`) and its rules/indexes; the `handles` collection if B1 takes that path; the block list under `private`. |
| `DATA_MODEL.md` | The queue model and its error enum; the handle decision; correct the `CourtDataset` claim (D1). |
| `ARCHITECTURE.md` | The new queue service in the ownership table; correct `CourtService`'s published properties (D1). |
| `UI_SHELL.md` | The run detail screen's presentation and its player-display subset; the `@handle` rationale after B1; the queue's surface; the new heat color roles once C5 ships. |
| `MAP_LAYER.md` | The `Detent`/`SheetState` model and container-height sizing (D1); court detail additions from C2; the location anchor after A0; C5's heat encoding, bucket thresholds, and cluster-aggregation policy. |
| `COURT_DATASET.md` | Where attribution surfaces (C2); correct the `loadError` claim (D1). |
| `BUILD_AND_CONFIG.md` | Emulator setup and how to run it (D3); the fixed UI test target (D2). |
| `GAPS.md` | Strike every row in D1's table that was a stale claim; add the honest client-side boundary on B3; restate A3's duplicate-run race. |
| `plans/LIVE_HEADCOUNT.md` | Reconcile with A2's `presence` decision — this plan is still unbuilt and shares its shape. |

## See also

- `plans/SCALE_UP.md` — the multi-city scaling roadmap this backlog sits under.
- `plans/FRIENDS.md` — Phases 4–5, which B2 and B3 draw from.
- `plans/LIVE_HEADCOUNT.md` — the `checkins` design A2 must be reconciled with
  before either is built.
- `GAPS.md` — the source for most of Track D, and itself the subject of D1.
