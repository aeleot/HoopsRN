# hoopsRN — Roadmap

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

What to do next, roughly in order of value per unit of effort. Each item names
the files it touches so it can be picked up cold.

This is **ordering**, not design. A specific feature's design lives in
`plans/`; what's wrong with what exists lives in `gaps/`. This page is the one
place that says which to reach for first.

`Scope: —` because it owns no source paths. Re-read it by hand whenever
something ships.

> **Deployed as of 2026-09-16:** rules and all indexes are live, including the
> Seasons atomic commit and the three burst-rate floors. Nothing below is
> blocked on a deploy.

---

## 0. The infrastructure decision, which gates six things

**Whether the project takes on server-side infrastructure** — Cloud Functions
on the Blaze plan, and/or App Check. It is one decision, and it unblocks:

- waitlist promotion (§3)
- **automatic** run completion — a scheduled sweep that finishes a run its host
  never marked. *Host-triggered* completion shipped 2026-09-18 on Spark and is
  not part of this decision: it's an ordinary client write against a host-only
  rule, the same authorization shape as cancel, and it already unstalled the
  Home stats card. What Blaze would add is completion without a host action, so
  a streak reflects the runs that happened rather than the ones someone
  remembered to record
- real rate limiting and the friend-request block list
- push notifications
- a real `userNameLower` backfill
- a server-side sweep for matches awaiting a report forever

Six features, one decision, and **it is worth making deliberately rather than
arriving at by accident** — which is what happens if each of the six gets
deferred separately for the same unstated reason. See
[`gaps/RATE_LIMITING.md`](gaps/RATE_LIMITING.md) for what rules genuinely
cannot do without it.

---

## 1. Decide how long a finished run stays listed

`Game.visibilityGrace` is **3 hours** after `scheduledTime`, applied in two
places that must agree: the Firestore query's cutoff, and `Game.isVisible(at:)`
re-applied on every rebuild. Raising it (6h was floated) is a one-constant
change in `Models/Game.swift`.

**The real issue is subtler and worth fixing at the same time: the query's
cutoff is fixed when the listener attaches.** A session left open overnight
keeps querying against last night's cutoff. `isVisible(at:)` hides those rows
client-side, so nothing wrong is displayed — but the query keeps paying for
them, and the `limit(to:)` budget is spent on runs that will never render.

`GameService.attachListeners()` recomputes the cutoff every time it runs, so a
re-attach picks up a fresh window — but it only runs on sign-in and on
recovery, so a healthy long-lived session still holds its original cutoff.

Options, cheapest first: recompute on foreground via `scenePhase` and
re-attach; or drop the range clause and filter entirely client-side (removes a
composite index, costs more reads); or move retirement server-side with a
scheduled Function writing `status: "completed"` — which is the automatic
completion §0 gates, now that the host-triggered half has shipped.

## 2. Backfill rules coverage for `games`, `friendships` and `users`

`firestore-tests/` exists and works — 102 tests against the emulator — but
covers **Seasons only**, because that was the phase that needed it. The
original three collections have no automated rules coverage; `friendships` was
walked through by hand once in August, `games` never.

The harness was the expensive part and it's already built. This is the cheapest
remaining assurance work in the project. See
[`gaps/TESTING.md`](gaps/TESTING.md).

## 3. Waitlist promotion — needs a Cloud Function

The update rule deliberately forbids writing another user's uid, so promotion
cannot be done by the leaving client. A triggered Function running with admin
credentials is the intended answer, and the same Function is the natural home
for `in_progress` / `completed`. **This is the first thing in the project that
requires the Blaze plan** — see §0.

## 4. Invites — the receiving half

Sending shipped 2026-08-15; the link currently goes nowhere. The work is URL
scheme registration, `.onOpenURL` handling, `GameService.fetchGame(byId:)` and
an `InviteJoinView` — **plus one real decision**: split the `games` read rule
into `get`/`list`, or add an `inviteToken`. An unguessable ID is not an
authorization model. Full detail in [`gaps/GAMES.md`](gaps/GAMES.md).

## 5. Friends' public runs (Phase 4)

`LocalRunsViewModel` gains `friendService`, `GameCard` grows an "N friends
here" badge. **No rules, index, or listener** — a client-side intersection of
two lists the app already holds, and `MainTabView` already has `friendService`
to pass in. The highest value-to-effort item on this page.

## 6. Confirm the tip-off default across time zones

`CreateGameViewModel.defaultTipOff` computes now + 1h rounded up to the quarter
hour. On the simulator at 00:54 local it produced a picker showing **5:00 AM** —
a three-hour gap that suggests a mismatch between the simulator clock and the
`DatePicker`'s display zone rather than the arithmetic. Reproduce on a device
before changing anything: `Date(timeIntervalSinceReferenceDate:)` rounding is
zone-independent, so the arithmetic is probably innocent.

## 7. Smaller, self-contained

- **Give `hooprOrange` a readable companion role** so it can be used as a
  foreground without failing AA in light mode. The tab bar's selected item is
  the most-seen instance, and `MainTabView`'s `.tint` is the single call site
  that would consume the new role first. See
  [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md).
- **Display the ODbL attribution** — `CourtService` discards it today, so this
  means holding the value as well as rendering it. An unmet licence obligation.
- **Rename `FindAMatchViewModel` to match `MapTab`.** The view was renamed when
  the third tab became Friends; its view model wasn't, so the file backing the
  court map is still named for matchmaking.
- **Delete the live test friendship** between the developer's account and
  `chaseallen122` in the production project, when it stops being useful.

---

## See also

- `INDEX.md` — where each subject actually lives.
- `gaps/` — what's wrong with what already exists.
- `plans/` — designs for things that don't exist yet.
