# hoopsRN — Roadmap

**Scope:** —
**Verified:** 2026-09-24 @ f30e4b2

What to do next, roughly in order of value per unit of effort. Each item names
the files it touches so it can be picked up cold.

This is **ordering**, not design. A specific feature's design lives in
`plans/`; what's wrong with what exists lives in `gaps/`. This page is the one
place that says which to reach for first. **Only open work is listed** — when
an item ships, delete it; git history has what was done.

`Scope: —` because it owns no source paths. Re-read it by hand whenever
something ships.

> **Deployed as of 2026-09-16:** rules and all indexes, including the Seasons
> atomic commit and the three burst-rate floors. The rules' last commit is a
> day later (`gaps/SEASONS.md`), so confirm the live ruleset matches before
> relying on that date.

**What's actually next:** §1 (verify the rebuilt UI on a device) costs nothing
but time and de-risks everything else; §0 gates the most; §3 is the largest
thing that needs no infrastructure decision.

---

## 0. The infrastructure decision, which gates six things

**Whether the project takes on server-side infrastructure** — Cloud Functions
on the Blaze plan, and/or App Check. It is one decision, and it unblocks:

- waitlist promotion (§2)
- **automatic** run completion — finishing a run whose host never marked it.
  Host-triggered completion already ships on Spark.
- real rate limiting and the friend-request block list
- push notifications
- a real `userNameLower` backfill
- a server-side sweep for Seasons matches awaiting a report forever

Six features, one decision, and **it is worth making deliberately rather than
arriving at by accident** — which is what happens if each of the six gets
deferred separately for the same unstated reason. See
[`gaps/RATE_LIMITING.md`](gaps/RATE_LIMITING.md) for what rules genuinely
cannot do without it, and `plans/LAUNCH_READINESS.md` §1 for App Check.

## 1. Verify the rebuilt UI on a device

The UI revamp (2026-09-21 → 24) rebuilt every screen. The simulator pass ran
on 2026-09-25 (both appearances, `.accessibility3`, Reduce Motion); what it
left — VoiceOver, game day and the result screen, Login, haptics, iOS 18 — is
listed in [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md). Alongside it, the two
two-account checks nothing else can close: the Seasons report/confirm flow
([`gaps/SEASONS.md`](gaps/SEASONS.md)) and a friend's join appearing live on
the other phone's run card.

## 2. Waitlist promotion — needs a Cloud Function

The update rule deliberately forbids writing another user's uid, so promotion
cannot be done by the leaving client. A triggered Function running with admin
credentials is the intended answer, and the same Function is the natural home
for `in_progress` / automatic `completed`. **This is the first thing in the
project that requires the Blaze plan** — see §0 and `plans/BACKLOG.md` D6.

## 3. Invites — the receiving half

Sending shipped 2026-08-15; the link currently goes nowhere. The work is URL
scheme registration, `.onOpenURL` handling, `GameService.fetchGame(byId:)` and
an `InviteJoinView` — **plus one real decision**: split the `games` read rule
into `get`/`list`, or add an `inviteToken`. An unguessable ID is not an
authorization model. Detail in [`gaps/GAMES.md`](gaps/GAMES.md); design in
`plans/BACKLOG.md` C6.

## 4. Confirm the tip-off default across time zones

`CreateGameViewModel.defaultTipOff` computes now + 1h rounded up to the quarter
hour. On the simulator at 00:54 local it produced a picker showing **5:00 AM** —
a three-hour gap that suggests a mismatch between the simulator clock and the
`DatePicker`'s display zone rather than the arithmetic. Reproduce on a device
before changing anything.

## 5. Smaller, self-contained

- **Delete the live test friendship** between the developer's account and
  `chaseallen122` in the production project, when it stops being useful.

---

## See also

- `INDEX.md` — where each subject actually lives.
- `gaps/` — what's wrong with what already exists.
- `plans/` — designs for things that don't exist yet.
