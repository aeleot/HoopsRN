# Plan — Scaling Up

**Status:** proposed, not started
**Drafted:** 2026-08-21
**Touches:** `firestore.rules`, `firestore.indexes.json`, `hoopr/Models/Game.swift`,
`hoopr/Services/GameService.swift`, `hoopr/Services/CourtService.swift`,
`hoopr/Resources/`, `hoopr.xcodeproj/project.pbxproj`,
`hoopr/Assets.xcassets/`, `context/COURT_DATASET.md`,
`context/database/DATABASE_SCHEMA.md`, `context/ARCHITECTURE.md`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a phase below ships, fold what's true into the
> dictionary entries named in "Documentation debt" and strike it from here.

## Context and decisions this plan assumes

This is the "how do we host more users" plan, written against four decisions
made when it was scoped:

1. **Stay on the Spark plan for now.** No Cloud Functions. Everything below
   is designed to work without one, and the items that genuinely can't are
   pulled into their own section (§7) rather than quietly assumed away.
2. **The growth axis is geography.** The plan is to add cities and metros
   beyond the current six-city Triangle-NC dataset, not just more users
   inside it. That decision reaches directly into §1 — it's what makes the
   current game-discovery query a correctness bug, not just a cost one.
3. **No firm user-count target.** The design below is sized to hold whether
   the next stop is a few thousand users or a few hundred thousand, rather
   than tuned to one number.
4. **Feature growth leads.** The roadmap in §4 is ordered by adoption value
   first. §1 is the one exception — it's written as a feature (multi-city
   support) but it's also the fix that prevents the app from getting
   measurably worse, for every user, every time a city is added. It has to
   ship as part of expanding to new cities, not after.

---

## 1. The fix that has to ship with the first new city

### What's true today

`GameService.attachListeners()` runs two queries. The one that matters here:

```swift
publicListener = database
    .collection(Collection.games)
    .whereField(Field.isPublic, isEqualTo: true)
    .whereField(Field.scheduledTime, isGreaterThan: cutoff)
    .order(by: Field.scheduledTime)
    .limit(to: Limit.published)   // 100
```

*(`GameService.swift:174-179`.)* There is no city, region, or geographic
filter anywhere in it. Every signed-in user's client asks Firestore for the
same thing: the soonest 100 public runs **on Earth**, ordered by tip-off
time. `LocalRunsViewModel` then filters that list down to the ones within the
user's `preferredRadius` of home.

### Why this is fine today and won't be after the next city

With one metro area, "the soonest 100 runs anywhere" and "the soonest 100
runs near me" are close enough to the same list that nobody notices. The
moment a second metro exists, they stop being the same list, in a way that
gets worse — not just more expensive — as more cities are added:

- **The query result is dominated by whichever city has the most activity**,
  not the user's own. A new city launches with a handful of runs; if any
  established city has 100+ public runs scheduled sooner, a brand-new user
  in the new city sees **zero runs near them**, not because none exist but
  because the global top-100 filled with someone else's city first. This is
  the cold-start problem the app will hit at the exact moment it's trying to
  prove itself in a new market.
- **Every client downloads and re-filters every public run everywhere,
  continuously.** A snapshot listener re-delivers the query's result set
  every time a document enters, leaves, or changes within it — so a run
  created or joined in any city re-triggers a snapshot on every other
  signed-in user's device, in every other city. Reads (and battery, and
  radio wake-ups) scale with **total platform activity**, not with a user's
  own city. This is the line item that turns "more cities" into a visibly
  larger Firestore bill and a slower app at the same time.
- **The 100-document cap is the only thing standing between this and an
  outright outage-shaped bug**, and it's a growing user base that spends it
  down. Multiply cities and this stops being a someday problem.

### The fix

Denormalize a region key onto `games` at write time, and query by it. The
client already has everything it needs to do this for free — `CourtService`
already holds the full `Court` for the chosen `courtId` before
`GameService.createGame` is ever called, and `Court.city` (`Models/Court.swift:21`)
is already populated for every court in the bundled dataset.

| Field | Type | Notes |
|---|---|---|
| `region` | string | The chosen court's `city`, copied in at create time. Immutable, like every other field describing the run itself. |

```swift
// GameService.createGame — one new field in an existing payload
Field.region: court.city,
```

```swift
// The query gains one equality clause
.whereField(Field.region, isEqualTo: userRegion)
.whereField(Field.isPublic, isEqualTo: true)
.whereField(Field.scheduledTime, isGreaterThan: cutoff)
.order(by: Field.scheduledTime)
.limit(to: Limit.published)
```

That needs a new composite index — `(region ASC, isPublic ASC, scheduledTime
ASC)` — alongside the two `firestore.indexes.json` already has, and a rules
change: the `create` allowlist and type-check gain `region` the same way
every prior field addition has (the two-step rule in
`database/DATABASE_SCHEMA.md` applies exactly as written).

**"Which region is the user's" is the one real product question here**, and
it's genuinely a few different shapes depending on how location is meant to
work once it's not hardcoded to Durham (see §4, Phase 1 — this plan assumes
that work lands alongside this one, since both touch the same "what is my
home area" concept):

- Coarsest and cheapest: the six-city list (soon to be N-city list) becomes a
  literal picker — onboarding asks "which city," `UserProfile` gets a
  `homeRegion` field, and that's the query key. Works today with zero new
  infrastructure.
- A step further: derive it automatically from `Court.city` of the nearest
  court to the user's device location, with the picker as an override/edit
  affordance rather than the only path in.
- **Don't reach for a geohash-and-radius scheme yet.** That's the right
  answer if runs need to be discoverable across a region boundary (someone
  five miles from a city line), but it's real complexity — a geohash field,
  range-query bounding-box math, more indexes — and nothing about "which
  city" needs it at this scale. Revisit only if region edges become a
  reported problem, not preemptively.


## 2. Court data has to stop being one bundled file

### What's true today

`courts.json` is one file, bundled in the app binary, loaded synchronously in
`CourtService.init()`. Adding a city today means: run
`tools/fetch_city_courts.py <City>`, commit the updated JSON, and ship an App
Store build. `CourtDataset.version` already exists specifically so a
CDN-hosted copy can be compared against the bundled one (`DATA_MODEL.md`) —
it's a seam that was built and never used.

### Why "many new cities/metros" strains this specifically

Every city added grows the binary every user downloads, whether or not they
ever visit that city — 213 courts across six cities is 86KB; growing to
dozens of metros nationally is a meaningfully larger number that every
install pays for regardless of relevance. Worse for the growth goal
specifically: **adding a city currently requires an App Store review cycle**.
That's fine for six cities added over a development season; it's a real
drag on the ability to respond to "can you add my city" demand once that
demand exists, which is the entire point of pursuing this growth axis.

### The fix

Keep the bundled file as the offline-first fallback — that reasoning in
`COURT_DATASET.md` (instant population, no dependency on a live service) is
still correct and shouldn't be abandoned. Add a path that can grow past it:

- Split `courts.json` by region (or fetch the current all-cities file plus
  per-region delta files) and host them on **Firebase Hosting**, which is
  available on the Spark plan — no billing change needed for this part.
- `CourtService` checks the hosted `version` per region against the bundled
  copy it shipped with, fetches the newer one if the network's up, and falls
  back to bundled on failure — the existing `version` field does exactly the
  comparison job it was built for.
- New cities become a data push plus a `version` bump, not an app release.
  The build scripts in `tools/` don't change; only where their output lands
  does.

---

## 3. Two things that block getting *any* new users, regardless of scale

These aren't architecture — they're the reason "host more users" could fail
before the rest of this plan is even relevant. Both are already named in
`GAPS.md`; repeating them here because a scaling plan that doesn't lead with
them is incomplete.

**S3.1 — Fix the iOS deployment target**
`GAPS.md` already flags this: deployment target is **iOS 26.5**, which
excludes nearly every device in current use, and nothing in the app calls a
26-only API. Confirm the real minimum the app needs and lower
`IPHONEOS_DEPLOYMENT_TARGET` accordingly in `project.pbxproj`.
*Acceptance criteria:*
- Target lowered to the actual minimum required by the SDKs in use (almost
  certainly far below 26.5).
- App builds and the existing test suites pass at the new target.
- This ships *before* any marketing push or App Store optimization work —
  it's a precondition for new users being able to install the app at all,
  not a nice-to-have alongside them.

**S3.2 — Ship a real app icon and accent color**
`AppIcon.appiconset` declares 14 slots with no images; `AccentColor.colorset`
has no color defined. The app currently presents the default placeholder icon
on every device — a strong, free signal to a prospective new user that the
app isn't finished.
*Acceptance criteria:*
- All required `AppIcon.appiconset` slots are populated.
- `AccentColor` is set (or the unused colorset is removed if every color is
  intentionally sourced from `Theme.swift` instead — either is fine, leaving
  it half-declared isn't).

---

## 4. Roadmap

Ordered by adoption value, per the "feature growth first" call — with §1 and
§3 folded in at the point they have to ship, not deferred to an "infra
phase" nobody gets to.

### Phase 0 — Ship-blockers (S3.1, S3.2)

Small, self-contained, and ahead of everything else because they cap how
many new users *can* arrive no matter what else ships.

### Phase 1 — Multi-city foundation (S1.1–S1.3, S2.1–S2.2)

This *is* the growth feature — "we're in your city now" — and it's also the
fix for §1's global-query problem. Shipping them together is the point: you
cannot respond to "expand to new cities" honestly without also fixing the
query that would make each new city actively worse for every existing user.

### Phase 2 — Invites: the receiving half

Already fully scoped in `GAPS.md` §4 and
`context/prompts/invitation_for_private_game.md`. Sending shipped
2026-08-15; nothing about *receiving* one exists yet. This is the single
highest-leverage adoption feature available: every invite link sent is an
acquisition channel for someone who doesn't have the app yet, and today that
link goes nowhere.

*Stories (restating GAPS.md §4 as shippable units):*

**S4.1 — Register the URL scheme and route a pending invite through cold start / sign-in**
*Acceptance criteria:* `hoopr` is registered under `CFBundleURLSchemes`;
`.onOpenURL` is handled in `hooprApp`; a `gameId` opened before sign-in
survives through login and lands the user on the right screen afterward.

**S4.2 — Split the `games` read rule into `get` vs. `list`, and pick the
authorization model deliberately**
*Acceptance criteria:* the rules change is a checked-in decision, not a
default — either an unguessable-ID `get` exception (documented as exactly
that: obscurity, not authorization) or an `inviteToken` field with a
rotation story. `database/DATABASE_SCHEMA.md` states which was chosen and
why.

**S4.3 — `GameService.fetchGame(byId:)` and an `InviteJoinView`**
*Acceptance criteria:* covers every state a link can land in — already on
the roster, full (offers the waitlist), aged out, deleted — each with a
distinct message, not a generic error.

### Phase 3 — Live headcount

Fully designed already in `plans/LIVE_HEADCOUNT.md`, phases 0–3, and
explicitly built to need no Cloud Functions. This is the feature that gives
someone a reason to open the app *before* leaving the house rather than only
when scheduling a run — the retention lever this roadmap needs opposite the
acquisition lever in Phase 2. Execute per that plan; nothing in this plan
changes its design. Its own §8 already flags the cold-start risk (counts
read zero until enough people check in) — worth the same honest framing here
that it gets there.

### Phase 4 — Friends, phases 4–5

Per `plans/FRIENDS.md` and the TODO in `GAPS.md`:

**S4.4 — Friends' public-runs badge (Phase 4)**: `LocalRunsViewModel` gains
`friendService`; `GameCard` shows "N friends here." Client-side intersection
of two lists the app already holds — no rules, index, or listener change.

**S4.5 — Friend profile detail**: tapping a friend shows name + home court,
once the visibility question `plans/FRIENDS.md` §6 raises is settled.

**S4.6 — Spark-compatible abuse containment (pulled forward from Phase 5)**:
`GAPS.md` names "no blocking, reporting, or rate limiting on friend
requests" as needing Cloud Functions. That's true for a *hard* server-side
cap, but a client-side throttle (a per-caller cooldown enforced the same way
the existing 300ms search debounce and one-write-in-flight guard already
work) plus a **block list** are both buildable now: a block list is just
another owner-only field a client checks before allowing a search result to
be actioned on — no Function required, since it's the *acting* user's own
client declining to send, not a server-enforced limit. Ship this as the
interim answer; the real rate limit stays flagged in §7 until Blaze.

### Phase 5 — Waitlist promotion, the Spark-compatible way

`GAPS.md` frames waitlist promotion as blocked on Cloud Functions, and a
server-authoritative version is — see §7. But the `games` update rule
doesn't actually require that: it forbids a caller from writing *someone
else's* uid into `playerIds`, not from writing *their own*. A waitlisted
player is already allowed to move themselves from `queuedPlayerIds` to
`playerIds`, the same write shape any join already uses — the rule change
needed is nothing; the app just never offers the action.

**S5.1 — Client-initiated self-promotion**
As a waitlisted player, when a confirmed player leaves and a seat opens, I
want to be offered a "claim your spot" action, so I don't have to keep
manually checking.
*Acceptance criteria:*
- Each waitlisted player's client observes the run's `playerIds` count (it
  already has the listener open) and surfaces a "Spot open — join now"
  action when `playerIds.size() < maxPlayers`.
- The write is the same self-membership write the app already performs; the
  existing membership-diff and `statusMatchesRoster()` rules validate it
  with no rules change.
- **Document the race honestly**: multiple waitlisted players can be offered
  the same open seat simultaneously; the first write to land wins, and
  every other client's attempt fails the `playerIds.size() <= maxPlayers`
  check and should show "spot's taken" rather than a raw permission error —
  this is a UX-layer race, not a data-integrity one, since the rules still
  enforce the cap either way.
- This is explicitly a stopgap for fairness (strict waitlist order isn't
  enforceable without a server deciding), not the final design — note that
  plainly rather than presenting it as equivalent to server-side promotion.

### Phase 6 — Privacy hardening

`GAPS.md` and `database/DATABASE_SCHEMA.md` both already flag this:
`homeCourtId` and `favoriteCourtIds` are a location pattern attached to a
named person, readable by any signed-in stranger, because `users` has no
field-level ACLs. This matters more with every user added, not less — it's
exactly the kind of debt that's cheap to defer at 100 users and expensive to
explain at 100,000.

**S6.1 — Split `users` into a public document and an owner-only `private` subcollection**
*Acceptance criteria:*
- `users/{uid}/private/settings` (or similar) holds `homeCourtId`,
  `favoriteCourtIds`, and anything future work would otherwise be tempted to
  bolt onto the public document.
- Rules on the subcollection: read and write, owner only — no allowlist
  gymnastics needed, since nobody else can read it at all.
- Migration path for existing documents: copy-then-delete per account, ideally
  folded into the same one-off script pass as S1.3 rather than a second
  separate migration.
- `database/DATABASE_SCHEMA.md` and `DATA_MODEL.md` updated to describe the
  split; this is the "real fix" both docs already say is owed.

---

## 5. Reliability work that scales with contributor count, not user count

Not urgent because of user growth directly, but the risk it guards against
gets more expensive the more surface area (cities, features, contributors)
sits on top of unverified rules.

**S7.1 — Rules coverage via the Firebase emulator**
`firebase emulators:exec` plus `@firebase/rules-unit-testing` doesn't need
Blaze — it's local. `GAPS.md` items #2 and #6 already call for this; every
phase above adds a new rules clause (`region`, the invite `get`/`list` split,
the `private` subcollection), which is exactly the kind of change
`FirestoreRulesParityTests` is explicit about *not* covering (it pins shared
constants, not rule behavior). Worth doing once, early, rather than once per
phase's rules change.

---

## 6. Read-cost sanity check

Rough, not a bill estimate — just enough to confirm the shape of §1's fix
matters more than any single number:

- **Before the fix:** every signed-in client holds a listener over the
  global top-100 public runs. Every write to any public run anywhere
  (create, join, leave, cancel) re-delivers a snapshot to **every** other
  online client, everywhere. Reads scale as *(total online users) × (total
  platform write rate)* — a product of two numbers that both grow with
  adoption, which is the shape that turns "we grew" into "our Firestore bill
  grew faster than we did."
- **After the fix:** a write to a run in Region A only re-delivers to
  clients whose listener is scoped to Region A. Reads scale as *(online
  users in a region) × (that region's write rate)* — the same shape, but
  now sized to one city instead of the whole platform. This is the
  difference between a cost curve that's flat per-region as you add regions,
  versus one that compounds.

This is the concrete version of the abstract point in §1: the fix isn't
optional polish on the growth plan, it's what makes "grow by adding cities"
sustainable rather than self-defeating.

---

## 7. Deferred until Blaze

Named here so they aren't rediscovered mid-phase-planning and aren't
silently dropped either. All genuinely need Cloud Functions (or another
paid service) and none are designed around in the plan above:

- **Push notifications** on friend request/acceptance, invite received, or
  "a spot opened up" — nothing can notify a *different* user's device from a
  client; that's what a Function triggered on write is for.
- **Server-authoritative waitlist promotion**, strict-order and race-free —
  §5's client self-promotion is the honest stopgap, not the replacement.
- **Scheduled `in_progress`/`completed` transitions** for `games` — currently
  substituted by `Game.visibilityGrace` aging runs out client-side.
- **Real rate limiting and reporting** on friend requests and, later,
  invites — §4's Phase 4 client-side throttle and block list are the
  interim answer.
- **Server-side `userNameLower` backfill as an ongoing migration** — the
  one-off Admin SDK script in S1.3 handles the current backlog once; new
  accounts always get it written at provisioning, so this isn't a recurring
  need, just worth naming so nobody proposes a Function for a problem that
  doesn't recur.

Worth a standing note: **none of the plan above requires this section to
happen first.** Every phase in §4 is designed to ship on Spark. This section
is a shopping list for whenever the Blaze decision is revisited, not a
blocker on anything above it.

---

## 8. Documentation debt

When a phase ships, fold it into the entry named and strike it here — same
convention `plans/FRIENDS.md` and `plans/LIVE_HEADCOUNT.md` already follow.

| Entry | Change |
|---|---|
| `database/DATABASE_SCHEMA.md` | `games.region`, `users.homeRegion`, the `users/{uid}/private/…` subcollection, the invite `get`/`list` split. |
| `DATA_MODEL.md` | `Game.region`; note the `users/private` split once S6.1 ships. |
| `COURT_DATASET.md` | The hosted-dataset layer alongside the bundled file, once S2.1 ships. |
| `ARCHITECTURE.md` | No vendor-boundary change expected — everything here stays inside existing services, unlike `plans/LIVE_HEADCOUNT.md`'s `CheckInService` addition. |
| `BUILD_AND_CONFIG.md` | The lowered deployment target (S3.1); the one-off backfill scripts (S1.3, S6.1) as documented manual operations. |
| `GAPS.md` | Strike the iOS 26.5 and app-icon items once S3.1/S3.2 ship; strike the invite-receiving gap once Phase 2 ships; update the waitlist-promotion item to describe the client-self-promotion stopgap once S5.1 ships. |
| `INDEX.md` | This plan's status line, as phases complete. |

## See also

- `GAPS.md` — most of §3–§7 above restates or extends a gap already named
  there; this plan is the "what to do about it, in what order" layer on top.
- `plans/FRIENDS.md`, `plans/LIVE_HEADCOUNT.md` — the two feature plans this
  roadmap sequences work around rather than duplicates.
- `database/DATABASE_SCHEMA.md` — the two-step rule every schema change
  above (`region`, `homeRegion`, the `private` subcollection) has to follow.
- `COURT_DATASET.md` — the bundled-dataset design §2 builds on top of rather
  than replaces.
