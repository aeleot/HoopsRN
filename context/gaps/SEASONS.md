# hoopsRN — Seasons gaps

**Scope:** —
**Verified:** 2026-08-29 @ 52680a6

What's unfinished, unverified, or deliberately capped in the Seasons feature —
squads, matchmaking, game day, and mutually-confirmed records. Read this before
assuming a Seasons behaviour works because the screen for it exists.

`Scope: —` because this is a cross-cutting narrative over code five other
entries own (`ARCHITECTURE.md`, `DATA_MODEL.md`, `UI_SHELL.md`,
`database/DATABASE_SCHEMA.md`, `BUILD_AND_CONFIG.md`), the same reason
`../GAPS.md` carries none. It can't be diffed, so it's re-read by hand every
pass.

**This is the feature-specific half of `../GAPS.md`**, not a duplicate of it.
Seasons entries live here and nowhere else; the app-wide list points here rather
than restating them.

**Not the same thing as `../plans/SEASONS.md` §7.** That section names what was
*never in scope for v1* — server-side matchmaking, skill rating, standings,
other formats. This file records what shipped and falls short of what a
reasonable person would expect from it. A §7 item only appears below when it has
a live consequence somebody will actually hit.

---

## Unverified — the honest headline

- **The live two-person confirm/dispute flow has never been exercised, and
  Seasons must not be described as working end to end.** Mutual confirmation's
  entire subject is *two different people agreeing or disagreeing with each
  other*, which no single-client test can reach.

  **Verified:** `firestore-tests/results.test.mjs` evaluates the real ruleset
  against two distinct authenticated leaders — agreement confirms, disagreement
  disputes, neither leader can write the other's report or manufacture an
  agreement alone, and a disputed match resolves by re-reporting.
  `SeasonGameTests` covers the derivation those rules mirror.

  **Not verified:** no two real accounts have ever queued, matched, played and
  reported to each other on device. So `ResultView`'s own rendering is unseen,
  and so is the live listener hand-off between two phones — the moment one
  leader's report is supposed to appear on the other's screen. A deferred manual
  test, not a known defect; it closes with a two-account pass and nothing in the
  code can close it.

- **Rules and indexes must be deployed before any of this works against the real
  project.** Phase 6 added a reporting path to `firestore.rules` and a second
  `seasonGames` composite index; a dry-run compiled them, which proves nothing
  about the deployed ruleset. Until `firebase deploy --only
  firestore:rules,firestore:indexes` runs, a report write fails
  `permission-denied` and an opponent's record read fails `failed-precondition`.

---

## A result that never lands

Three ways a played match can fail to reach anybody's record. All are direct
consequences of mutual confirmation having no server and no arbiter, and none of
them is currently surfaced as anything but silence.

- **A match awaiting one leader's report waits forever.** There is no timeout, no
  forfeit, and no nudge. If the other squad's leader stops opening the app, the
  match sits `scheduled` indefinitely, counts for nobody, and the only sign is
  the result screen saying "Waiting on {opponent}". A server-side sweep is the
  obvious fix and needs the same Cloud Function everything else here is blocked
  on; a client-side one can't be trusted, because the client that benefits from
  a forfeit is the one that would be declaring it.

- **A dispute has no arbiter and no expiry.** `../plans/SEASONS.md` §8 accepts
  this — disputed games count for nobody, and re-reporting is allowed — but the
  practical shape is worth stating: two leaders who each believe they won leave a
  permanently disputed match, and neither squad's record moves. Designed, and
  still a dead end when it happens.

- **A mutually-agreed *wrong* result is permanent.** `confirmed` is deliberately
  not re-reportable (`SeasonGame.isReportable`), because a leader who could
  re-report a settled match could turn their own loss back into a dispute
  unilaterally. The cost is the mirror case: if both leaders mis-tap the same
  way, there is no correction path at all — not for them, and not for anyone.
  Reopening a confirmed match safely needs *both* leaders to agree to reopen it,
  which is a second mutual-confirmation handshake nobody has designed.

---

## Named ceilings

Limits that are working as built, and will surprise somebody anyway.

- **A season game's notifications are only scheduled by a client that's actually
  open.** `NotificationService` schedules the T-60/T-0/T+90 reminders the moment
  `MatchmakingViewModel` sees a match land — a client-side reaction to a
  Firestore snapshot, not a server event. A squad member whose app never launches
  between the match being made and tip-off never has those requests on their
  device, and finds out only if a squad-mate's phone happened to be open. Real
  push needs FCM (not linked) plus a Cloud Function triggered off the
  `seasonGames` write — the same Blaze-plan requirement `../plans/SEASONS.md`
  §0.1 and §7 name for server-side matchmaking. The local-notification design's
  known ceiling, not a bug in it.

- **A person on more than ten squads sees matches for the first ten.**
  `SeasonGameService` uses `array-contains-any`, whose ceiling is Firestore's ten
  — named in `Limit.observedSquads` rather than left as a silent truncation, but
  still a truncation. Nothing in the app stops an eleventh squad being joined.

- **Only the primary squad gets the live match card.** `SeasonsTab` renders
  `MatchmakingCard` for `viewModel.primarySquad`; a second squad's match is
  reachable only through its own detail screen. Queueing is likewise
  primary-squad-only from squad home. Fine while almost everyone has one squad,
  and the wrong shape the moment they don't.

- **An empty pool is the default experience in a new city**, not the edge case.
  `../plans/SEASONS.md` §8 names relaxation plus honest UI as the mitigation, and
  both shipped — but the *seeding* idea it floats (a one-sided open challenge
  anyone can accept) was never built. With two squads in a region, matchmaking is
  two leaders agreeing to queue at the same time.

- **Forging a win takes two colluding squads.** Stated so it isn't mistaken for a
  defect: mutual confirmation is the ceiling without a server, and
  `../plans/SEASONS.md` §7 says so. It is the standard a rec-league scoresheet
  meets, not cryptographic integrity.

---

## Fixed, and worth remembering

- **Two matches for one pair used to be the *ordinary* outcome, not a rare
  one.** This file recorded it as a narrow window — a third squad re-claiming a
  stale ticket whose game already existed — and said rules could not prevent it
  because rules cannot query. Both halves were wrong.

  The real cause was two squads picking *each other*. A match was made in three
  writes, the first of which claimed a **single** ticket and leaned on Firestore
  serializing contested writes to one document. Two mutual claims touch two
  different documents, so nothing serialized them: both won, both clients wrote a
  match, and both squads were told they had more than one scheduled. With two
  squads queued in a region that is what normally happened.

  It never needed a query — only a read set wide enough to contend. The commit
  now reads and writes both tickets and the match in one transaction, each of
  the three documents proving the other two with `getAfter()`, and a ticket may
  only go `open` -> `matched`. `firestore-tests/claim-race.test.mjs` races the
  mutual case fifteen rounds and asserts exactly one match survives.

  Three things went with it: the `claimed` status, `MatchRules.staleClaim` and
  its four-places-that-must-agree, and the two-writer `matched` transition. All
  three existed to clean up after a gap that no longer exists.

- **A spent ticket used to read as a live search.** Nothing deletes a ticket
  once it is spent; it ages out on `expiresAt`, up to a day later. The card read
  any non-nil ticket as "searching", so the moment a match stopped being live —
  played and confirmed, cancelled, or simply aged out — a squad was shown a
  spinner and a timer counting from when they first queued, with a "Cancel
  search" button that cancelled nothing. `MatchTicket.isSearching` is now the
  only question that state may ask, and `MatchmakingViewModelTests` pins each
  way a match can end.

  The same stale ticket also blocked re-queueing: a `setData` over it is an
  *update*, which no rule admits, so the squad was refused for as long as the
  ticket lived. `MatchmakingService.queue` now deletes a spent ticket first.

## Costs accepted on purpose

- **An opponent's crest costs one extra read per match card.** `seasonGames`
  denormalizes squad *names* so history survives a disbanded squad, but not
  `iconKey`/`colorKey` — so `MatchmakingViewModel` and `ResultViewModel` each
  fetch the opponent squad to draw one. Taken over denormalizing two more fields
  onto every match: a crest is decoration, a failed read falls back to a redacted
  placeholder, and the alternative is two more copies that can drift from
  `squads`. Revisit only if a standings screen ever renders many crests at once.

- **An opponent's record is a query, not a field.** The deliberate cost of
  `squads` storing no `wins`/`losses` — see `database/DATABASE_SCHEMA.md`. One
  extra read to show a record, in exchange for a number nobody can type.

---

## Not built, and known not to be

`../plans/SEASONS.md` §7 is the authority; these are the ones with a live
consequence today rather than a purely future one.

- **No kicking a member mid-season, and no leader transfer.** The rules can
  express both (a leader-only single-uid removal); a squad whose leader goes
  inactive can only be left and rebuilt, and a squad carrying someone who has
  stopped playing carries them all season.
- **No standings or leaderboards.** A record exists per squad and there is
  nowhere to compare it, which is the obvious next question once two squads have
  played. Blocked on the derived record being cheap at scale — i.e. on the
  counter cache `database/DATABASE_SCHEMA.md` deliberately defers.
- **No skill rating.** The record-proximity gate in `MatchRules` is already the
  hook one would plug into.

---

## See also

- `../GAPS.md` — the app-wide list. Everything not Seasons.
- `../plans/SEASONS.md` — §7 for what was never in scope, §8 for the risks this
  file's ceilings came from.
- `../database/DATABASE_SCHEMA.md` — the reporting rules and why a record is
  trustworthy.
- `../BUILD_AND_CONFIG.md` — the rules suite, and why a dry-run is not a test.
