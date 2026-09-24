# hoopsRN — Gaps

**Scope:** —
**Verified:** 2026-09-24 @ f30e4b2

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
| [`gaps/SEASONS.md`](gaps/SEASONS.md) | Squads, matchmaking, game day, recorded results. The unverified two-person confirm flow, the ways a played match can fail to reach a record, the local-notification ceiling, one-squad-per-person being app-enforced only, and what was never in scope. |
| [`gaps/GAMES.md`](gaps/GAMES.md) | Runs: the invite link that can be sent but not opened, no waitlist promotion, no `in_progress`, and no *automatic* completion — a host marks a run complete by hand or it just ages out. |
| [`gaps/FRIENDS.md`](gaps/FRIENDS.md) | Discovery and requests. No blocking, reporting or rate limiting; the client's half of the simultaneous-request collision has never run. |
| [`gaps/PROFILES.md`](gaps/PROFILES.md) | `users/{uid}`: the search-key backfill that completes one account at a time, what a world-readable profile leaks, what sign-in still can't do. |
| [`gaps/RATE_LIMITING.md`](gaps/RATE_LIMITING.md) | What bounds how fast a client can write, what doesn't, and why most of it needs infrastructure the project doesn't have. |
| [`gaps/TESTING.md`](gaps/TESTING.md) | What the two suites cover — all seven collections have rules coverage as of 2026-09-20 — what they still don't, and the recovery path never exercised for real. |
| [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md) | The form guide's colour-only order, the pairings the suite doesn't assert, and the VoiceOver / Reduce Motion / `.accessibility3` pass the rebuilt UI has never had on a device. |
| [`gaps/ASSETS_AND_DATA.md`](gaps/ASSETS_AND_DATA.md) | The unset accent colour, where the ODbL notice is (and isn't), two scripts that can't be re-run cleanly, six-city coverage. |
| [`gaps/CONFIGURATION.md`](gaps/CONFIGURATION.md) | The half-finished hoopr→hoopsRN rename, and the iOS 18 fallback path nothing has run. |

**A feature earns its own file** once its gaps would crowd this list out of
readability. Until then it belongs in the closest existing one — not here.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

None outstanding as of 2026-09-24. Past corrections are in git history rather
than listed here: this page records drift that exists, not drift that was
fixed. When something reads as stale, correct it in place; add a row only if it
has to be left for later, and delete the row when it's fixed.

---

## See also

- [`ROADMAP.md`](ROADMAP.md) — what to do next, in order. A gap says what's
  wrong; the roadmap says what to reach for first.
- [`INDEX.md`](INDEX.md) — where each subject lives.
- [`plans/`](plans/) — designs for work that doesn't exist yet.
