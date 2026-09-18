# hoopsRN — Runs and invites gaps

**Scope:** —
**Verified:** 2026-09-18 @ de875eb

What's unfinished about `games` — the run lifecycle, the invite link that can
be sent but not opened, and the waitlist that doesn't move.

`Scope: —` because this is a narrative over code `DATA_MODEL.md`,
`database/DATABASE_SCHEMA.md` and `UI_SHELL.md` own. It can't be diffed, so
it's re-read by hand every pass.

---

## An invite link can be sent but not opened

A host can copy `hoopsrn://game/{id}` from the create sheet and from the run's
card in Queued Games (shipped 2026-08-15), and that's the whole of it:
`hoopsrn://` isn't a registered URL scheme, nothing implements `.onOpenURL`,
and the `games` read rule still refuses a non-member — so a recipient who taps
the link gets nothing. **An invite-only run still holds only its host.**

What's left, and the middle item is a decision rather than a task:

- Register `hoopsrn` under `CFBundleURLSchemes` — the scheme `InviteLink`
  actually mints, not `hoopr` — and handle `.onOpenURL` in `hooprApp`, stashing
  the pending `gameId` across a cold start and a sign-in.
- **Split the `games` `read` rule into `get` (any signed-in user, by direct
  document reference) and `list` (unchanged).** This is the decision, not a
  detail: *an unguessable ID is not an authorization model.* The alternative is
  an `inviteToken` field checked in the rule, which is a schema change and a
  rotation story. Pick one deliberately.
- `GameService.fetchGame(byId:)` plus an `InviteJoinView` covering the states a
  link can land in: already on the roster, full (waitlist), aged out, deleted.

*(A 219-line worked design for this lived in `context/prompts/` until
2026-09-16, when the prompts directory was removed. The decision above is the
load-bearing part of it; the rest was a view-model skeleton and an acceptance
checklist that a future implementer would re-derive anyway. `git log` has it.)*

---

## No waitlist promotion

When a confirmed player leaves a full run, the freed slot isn't handed to the
first waitlisted player — **the update rule forbids writing another user's uid,
deliberately.** That is the same rule that makes every roster write safe, so
this isn't a bug to fix in rules; it needs either a host action ("promote"), or
a Cloud Function running with admin credentials.

---

## `in_progress` is still never written

**`completed` now is** (2026-09-18). A host gets a "Mark complete" control on
their own run's card once it has started, which calls
`GameService.completeGame(id:)` and writes `status: completed` + `completedAt`
through the host-only `allow update` clause that had been sitting in
`firestore.rules` unused. That closed the Home stats card gap this section used
to describe: `completedGames` now receives documents, `HomeViewModel`
recalculates off them, and `hasStats` turns true on a real account without
anyone hand-editing `users/{uid}`.

`in_progress` remains declared and never written. Nothing distinguishes it from
`open` on any screen, so there's no control to hang on it — and a run that is
never completed still ages out `Game.visibilityGrace` (3h) after tip-off, which
is what retires the ones nobody marks.

**What completion still doesn't do, and won't without a Cloud Function:**
happen by itself. A run whose host never taps the control is never completed —
it just ages out — so the streak reflects the runs a host *recorded*, not the
runs that happened. An automatic sweep needs a scheduled function, which needs
the Blaze plan; `ROADMAP.md` §0 keeps the two separated now that the
host-triggered half has shipped on Spark.

**Completion carries no attendance claim, deliberately.** There is no check-in
concept anywhere in the schema, so the only thing `completed` asserts is *this
run happened*. A host who turned up alone can mark their own run complete and
take the streak week for it — `canComplete` does not consult the roster, and a
floor there was considered and rejected: it would invent a guarantee the
ruleset doesn't make (the rule itself checks only host, not-already-completed,
and the three-key allowlist), and the client is not where an unforgeable count
could be enforced anyway. These are self-reported profile counters on a
document the owner writes, which `database/DATABASE_SCHEMA.md` already records
as forgeable. Read the streak as a personal activity log, not a competitive
claim. **Decided 2026-09-18** — if this is revisited, it's a product call about
what the number means, not a bug.

**There is no un-complete path**, by design: the rule's
`resource.data.status != 'completed'` precondition refuses a second write. A
host who completes the wrong run cannot reverse it, and cannot cancel it either
— the delete rule is separate and still permits it, but the run has already left
every list, so there is no UI that reaches it. That is a real rough edge and the
first thing to revisit if anyone hits it in practice.

---

## Named ceilings

- **Friends' private runs stay invisible.** Friendship doesn't factor into the
  `games` read rule and can't without a rules change — it overlaps the invite
  decision above, and should be settled with it rather than separately.
- **No occupancy or check-in.** Games exist — scheduling, joining, leaving,
  cancelling — but "is anyone at this court *now*" is unanswerable. See
  `../plans/LIVE_HEADCOUNT.md`.
- **Game cards show court, time, roster, distance and capacity only.** Player
  names, avatars, and any per-run detail screen are unbuilt. Names would need a
  read across `users` and a privacy decision, not just a UI — see
  [`PROFILES.md`](PROFILES.md).
- **No cap on runs per host**, which is the `games` instance of the pattern in
  [`RATE_LIMITING.md`](RATE_LIMITING.md): a flood of public runs can crowd real
  ones out of the client's 100-document query window for a whole city.

---

## See also

- `../database/DATABASE_SCHEMA.md` — the `games` rules, including the roster
  membership diff these gaps keep running into.
- `../plans/LIVE_HEADCOUNT.md` — the design that would close the occupancy gap.
- `../plans/STATS_CARD.md` — the card completion now feeds. Its §11 lists the
  completion UI under Future Work and its §14 treats it as an external
  dependency; both were written before it shipped.
- [`RATE_LIMITING.md`](RATE_LIMITING.md) — why "needs a Cloud Function" appears
  three times on this page.
