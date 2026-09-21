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
| [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md) | The one tracked WCAG failure — brand orange as a foreground in light mode, at 3.17:1 against a 4.5:1 text floor — pinned by a test that fails when it's fixed. |
| [`gaps/ASSETS_AND_DATA.md`](gaps/ASSETS_AND_DATA.md) | The unmet ODbL licence obligation, two scripts that can't be re-run cleanly, the unset accent colour. (The placeholder icon was fixed 2026-09-20.) |
| [`gaps/CONFIGURATION.md`](gaps/CONFIGURATION.md) | The half-finished hoopr→hoopsRN rename. The deployment target and the over-declared platforms were fixed 2026-09-20; what's left there is the iOS 18 fallback path nothing has run below iOS 26. |

**A feature earns its own file** once its gaps would crowd this list out of
readability. Until then it belongs in the closest existing one — not here.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

**Outstanding — four code comments, found 2026-09-21 and deliberately left
alone**, because that pass was docs-only and each is a one-line comment edit.
The correct figures are in [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md),
recomputed from `Theme.swift`.

| Where | Says | Actually |
|---|---|---|
| `Support/InviteLink.swift:13` | "see `GAPS.md` §4" | This page has no numbered sections; the invite gap is in [`gaps/GAMES.md`](gaps/GAMES.md). |
| `Views/Tabs/CourtGameRow.swift:104` | `hooprOrange` is 2.34:1 on `hooprFill` in light mode | 2.91:1. |
| `Support/Theme.swift:62–64` | black clears 9.17 / 10.24 on `hooprOrange`, 7.42 / 9.17 on `hooprDarkOrange` | 6.62 / 7.15 and 5.46 / 5.89. Still AA, with far less margin — and the same file says 6.61 / 7.15 at line 30. |
| `hooprTests/ThemeContrastTests.swift:208–210, 242` | 2.55 / 2.34 light, 9.33 / 7.56 / 6.19 dark, "gets ~2.55:1" | 3.17 / 2.91 light, 7.15 / 5.79 / 4.74 dark. |

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
