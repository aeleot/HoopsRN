# hoopsRN — Runs and invites gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

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

## No host controls for `in_progress` / `completed`

Both statuses are declared and neither is ever written; runs age out
`Game.visibilityGrace` (3h) after tip-off instead.

**This also stalls the Home stats card.** `HomeViewModel` only calls
`UserProfileService.refreshStats` when `GameService.completedGames` publishes a
non-empty snapshot, and that listener queries `status == "completed"` — the
status nothing writes. So `completedGameCount` stays absent and `hasStats`
stays false for every account, new or existing, until something marks a game
complete. The only way to see the card today is hand-editing
`completedGameCount` / `participationStreak` / `lastCompletedAt` directly on a
`users/{uid}` document.

`plans/STATS_CARD.md` §14 names this as an external dependency it assumes gets
built separately, and confirms neither Phase 4 nor Phase 5 closes it — the
completion UI is listed under its §11 Future Work, unscheduled.

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
- `../plans/LIVE_HEADCOUNT.md`, `../plans/STATS_CARD.md` — the two designs that
  would close the occupancy and completion gaps.
- [`RATE_LIMITING.md`](RATE_LIMITING.md) — why "needs a Cloud Function" appears
  three times on this page.
