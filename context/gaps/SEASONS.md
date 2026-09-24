# hoopsRN — Seasons gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

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

It records what shipped and falls short of what a reasonable person would
expect, and — at the end — what was never in scope, so neither gets
rediscovered.

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
  project — and `ROADMAP.md` records that they were, on 2026-09-16, including
  the atomic commit and the three burst-rate floors.** Phase 6 added a reporting
  path to `firestore.rules` and a second `seasonGames` composite index; a
  dry-run compiled them, which proves nothing about the deployed ruleset. What's
  left is the standing rule: any *later* rules or index change fails the same
  way until it is redeployed — a report write `permission-denied`, an
  opponent's record read `failed-precondition`.

  **Not checkable from the repo:** the rules' last commit is 2026-09-17
  (`2c75b14`), a day *after* the recorded deploy. Confirm the live ruleset
  matches it before trusting either date.

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

- **A dispute has no arbiter and no expiry.** The design accepts this —
  disputed games count for nobody, and re-reporting is allowed — but the
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
  `seasonGames` write — the same Blaze-plan requirement server-side matchmaking
  has (see "Not built" below). The local-notification design's known ceiling,
  not a bug in it.

- **One squad per person is enforced by the app, not the server.** Creating a
  squad and accepting an invite are refused while you're on another one
  (`Squad.membershipBlock`, asked by `SquadService` as the enforcement and by
  the inbox row so it stops offering the Join). `firestore.rules` can't back it:
  rules can't query, so there is no way to ask "which squads is this uid on".
  Closing it server-side would take a per-person document written atomically
  with every create, join and leave — the `matchTickets/{squadId}` trick with
  the uid as the ID — plus stale-entry cleanup when a leader disbands, a
  backfill for existing members, and a rules deploy. Not built; a modified
  client can still join a second squad.

  **The backstop is thinner than it looks.** `MatchRules` skips a pairing of two
  squads that share a player, so an honest client never plays someone against
  themselves — but that is a client-side filter. `firestore.rules` doesn't check
  it either: the ticket's `memberIds` is pinned to the squad document so that a
  server rule *could*, and no rule reads it. So a person on two squads can be
  matched against themselves by a modified client. That was already true before
  this rule and is the same gap, not a new one.

  Three edges of it will surprise somebody:

  - **It isn't retroactive, and the way out was removed.** Anyone who joined a
    second squad before it landed still has both, and is refused a third. The
    "Your other squads" rows that let them reach the extra one to leave it were
    **deleted 2026-09-24 without checking that nobody was left on two** — that
    needs a query over production `squads`, which nothing in the repo can run.
    Such a person now sees only their most recently changed squad (`SeasonsTab`
    renders `primarySquad`) and can't open the other from the app; the fix is to
    remove their uid from the extra squad's `memberIds` by hand in the console,
    or to restore the rows (git history has `otherSquads(besides:)`). The
    ten-squad `array-contains-any` ceiling
    (`SeasonGameService.Limit.observedSquads`) is no longer reachable through
    the app.
  - **The invite picker can't see it.** A leader can invite a friend who is on
    another squad; that friend's inbox row loses its Join and says to leave
    first. The leader is never told. Knowing would cost a read per friend on
    every picker open.
  - **A leader has to disband to move.** A leader can't leave (see "Not built"
    below on leader transfer), so "leave it to join another squad" is, for them,
    "disband it" — which ends the squad for everyone on it.

- **An empty pool is the default experience in a new city**, not the edge case.
  The mitigation was relaxation plus honest UI, and both shipped — but the
  *seeding* idea (a one-sided open challenge any squad can accept) was never
  built. With two squads in a region, matchmaking is
  two leaders agreeing to queue at the same time.

- **Forging a win takes two colluding squads.** Stated so it isn't mistaken for a
  defect: mutual confirmation is the ceiling without a server. It is the standard a rec-league scoresheet
  meets, not cryptographic integrity.

---

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

Out of reach by design, not by oversight — recorded here so nobody spends a day
rediscovering them. (The Seasons design plan these came from shipped and was
removed on 2026-09-24; it's in git history.)

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
- **No server-side matchmaking and no real push.** Both need Cloud Functions on
  the Blaze plan (`../ROADMAP.md` §0). Matchmaking is client-side "pull with a
  lock" for that reason — see `../database/DATABASE_SCHEMA.md` § `matchTickets`.
- **No cross-region play.** A squad's pool is its `region`, today `Court.city`;
  matching across regions waits on `../plans/SCALE_UP.md` S1.1's real region key.
- **3v3 only.** `format` has been in the schema from day one, so 1v1 and 5v5 are
  an allowlist entry and a roster bound each, not a migration.

---

## See also

- `../GAPS.md` — the app-wide list. Everything not Seasons.
- `../database/DATABASE_SCHEMA.md` — the reporting rules and why a record is
  trustworthy.
- `../BUILD_AND_CONFIG.md` — the rules suite, and why a dry-run is not a test.
