# hoopsRN — Gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

**Read this before trusting a code comment**, and before assuming a feature
exists because a field or a tab does.

This page is a router. Every gap lives in exactly one file under
[`gaps/`](gaps/), because a gap recorded in two places is two gaps that drift.
Nothing below restates what those files say.

`Scope: —` because it owns no source paths. Re-read it by hand whenever
something ships.

---

## Where to look

| File | What's in it |
|---|---|
| [`gaps/SEASONS.md`](gaps/SEASONS.md) | Squads, matchmaking, game day, recorded results. The unverified two-person confirm flow, the ways a played match can fail to reach a record, the local-notification ceiling. |
| [`gaps/GAMES.md`](gaps/GAMES.md) | Runs: the invite link that can be sent but not opened, no waitlist promotion, no `in_progress`, and no *automatic* completion — a host marks a run complete by hand or it just ages out. |
| [`gaps/FRIENDS.md`](gaps/FRIENDS.md) | Discovery and requests. No blocking, reporting or rate limiting; the client's half of the simultaneous-request collision has never run. |
| [`gaps/PROFILES.md`](gaps/PROFILES.md) | `users/{uid}`: the search-key backfill that completes one account at a time, what a world-readable profile leaks, what sign-in still can't do. |
| [`gaps/RATE_LIMITING.md`](gaps/RATE_LIMITING.md) | What bounds how fast a client can write, what doesn't, and why most of it needs infrastructure the project doesn't have. |
| [`gaps/TESTING.md`](gaps/TESTING.md) | What the two suites cover — all seven collections have rules coverage as of 2026-09-20 — what they still don't, and the recovery path never exercised for real. |
| [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md) | Two screens that break at `.accessibility3` (`StatsCard` mid-word, the map's court card truncating its own name) and the pairings the suite doesn't assert. The brand-orange AA failure that used to lead this page **closed 2026-09-21**. |
| [`gaps/ASSETS_AND_DATA.md`](gaps/ASSETS_AND_DATA.md) | The unmet ODbL licence obligation, two scripts that can't be re-run cleanly, the unset accent colour. (The placeholder icon was fixed 2026-09-20.) |
| [`gaps/CONFIGURATION.md`](gaps/CONFIGURATION.md) | The half-finished hoopr→hoopsRN rename. The deployment target and the over-declared platforms were fixed 2026-09-20; what's left there is the iOS 18 fallback path nothing has run below iOS 26. |

**A feature earns its own file** once its gaps would crowd this list out of
readability. Until then it belongs in the closest existing one — not here.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

**Outstanding — one code comment, found 2026-09-21 and deliberately left
alone**, because that pass was docs-only and this is a one-line comment edit:

| Where | Says | Actually |
|---|---|---|
| `Support/InviteLink.swift:13` | "see `GAPS.md` §4" | This page has no numbered sections; the invite gap is in [`gaps/GAMES.md`](gaps/GAMES.md). |

**Corrected in code on 2026-09-21**, because Phase 1 of the UI revamp edited the
files anyway: the other three of that pass's four — `CourtGameRow.swift`'s
"2.34:1 on `hooprFill`", `Theme.swift`'s black-on-orange figures (it said 9.17 /
10.24 on `hooprOrange` and 7.42 / 9.17 on `hooprDarkOrange`; the values are 6.62
/ 7.15 and 5.46 / 5.89), and `ThemeContrastTests`' "2.55 / 2.34 light" — plus a
fifth nobody had listed: `MAP_LAYER.md` quoted the heat ramp's stop 0 as
`F79331`, the value before the 2026-08-22 retune, while `CourtHeatTests` pinned
`EE6730`. And one that was a *claim* rather than a number: `Theme.swift` said
black was "the only foreground that clears AA against every stop of the heat
ramp" on the map pin's count. It is 4.01:1 and 3.43:1 on the two deepest.

**Corrected in the docs on 2026-09-21**, listed once so they aren't re-reported:

- `ARCHITECTURE.md` and `CLAUDE.md` said `LocationService` publishes no device
  coordinate and keeps its delegate only so MapKit's blue dot can draw.
  `homeLocation` has followed the device since 2026-08-27, and
  `gaps/ASSETS_AND_DATA.md` had that right — the two entries a reader is sent to
  *first* were the wrong ones.
- `CLAUDE.md` said the deployment target is iOS 26.5 (it is 18.0 and
  iPhone-only, since 2026-09-20), and that `permission-denied` "stops the
  listener" (the supervisor re-attaches after every error).
- `gaps/ACCESSIBILITY.md`'s ratios were from before the 2026-08-22 retune of
  `hooprOrange`, and its list of affected sites was about a quarter of the real
  set.
- `gaps/GAMES.md` still said a run ages out after 3h (it is 4h) and that cards
  show only court, time, roster, distance and capacity (they now show a
  friends-here count); `gaps/FRIENDS.md` listed the friend profile sheet as
  unbuilt; this page's own rows still advertised the placeholder icon and
  "verified by hand once".
- "Boundary-tested at 4s / 6s" — in `gaps/RATE_LIMITING.md`,
  `database/DATABASE_SCHEMA.md` and `PRODUCT_OVERVIEW.md`. The floors are tested
  at 0s and 6s, which doesn't pin the boundary.
- `INDEX.md` said the stats card stays empty until something writes
  `completed`; a host has been able to since 2026-09-18.

The row before all of these — prompts citing a `firestore.rules` path that
pointed into `"hoopr project info/…"` — resolved itself on 2026-09-16 when both
`context/prompts/` and that directory were removed.

Every earlier row was corrected in the code on 2026-08-21 rather than recorded
here, and they're listed once so they aren't re-reported: `UserProfile`'s
`homeCourtId` doc (it *is* written), `UserProfileTests`' matching comment,
`build_courts.py`'s `LAUNCH_CITIES`, `fetch_city_courts.py`'s reference to the
deleted `CourtSearchService.swift`, `CourtRow`'s dead `badges`, `CourtTests`'
"six screens" claim, `firestore.rules` protecting a removed `email` field, and
`MainTabView`'s "three tabs".

Resolved by the 2026-08-21 rebuild and kept only so they aren't rediscovered:
`database/USER_PROFILE_WORKFLOW.md` carried a `Scope` of path *fragments* that
matched nothing in the repo, so `check_context_drift.py` reported it "current"
for two weeks while its code map pointed at a deleted file. It declares no
scope at all now and is revisited by hand.

**Anything that reads as stale should be corrected in place and recorded here**,
not left to be rediscovered.

---

## See also

- [`ROADMAP.md`](ROADMAP.md) — what to do next, in order. A gap says what's
  wrong; the roadmap says what to reach for first.
- [`INDEX.md`](INDEX.md) — where each subject lives.
- [`plans/`](plans/) — designs for work that doesn't exist yet.
