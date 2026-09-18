# hoopsRN — Gaps

**Scope:** —
**Verified:** 2026-09-18 @ de875eb

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
| [`gaps/FRIENDS.md`](gaps/FRIENDS.md) | Discovery and requests. No blocking, reporting or rate limiting; verified by hand once and never since. |
| [`gaps/PROFILES.md`](gaps/PROFILES.md) | `users/{uid}`: the search-key backfill that completes one account at a time, what a world-readable profile leaks, what sign-in still can't do. |
| [`gaps/RATE_LIMITING.md`](gaps/RATE_LIMITING.md) | What bounds how fast a client can write, what doesn't, and why most of it needs infrastructure the project doesn't have. |
| [`gaps/TESTING.md`](gaps/TESTING.md) | What the two suites cover, what they don't (`games`, `friendships`, `users` have no rules coverage), and the recovery path never exercised for real. |
| [`gaps/ACCESSIBILITY.md`](gaps/ACCESSIBILITY.md) | The one tracked WCAG failure — brand orange as a foreground in light mode — pinned by a test that fails when it's fixed. |
| [`gaps/ASSETS_AND_DATA.md`](gaps/ASSETS_AND_DATA.md) | Placeholder app icon, the unmet ODbL licence obligation, two scripts that can't be re-run cleanly. |
| [`gaps/CONFIGURATION.md`](gaps/CONFIGURATION.md) | The half-finished hoopr→hoopsRN rename, the iOS 26.5 deployment target, platforms the UI doesn't support. |

**A feature earns its own file** once its gaps would crowd this list out of
readability. Until then it belongs in the closest existing one — not here.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

**Nothing is outstanding.** The last row this table carried — prompts citing a
`firestore.rules` path that pointed into `"hoopr project info/…"` — resolved
itself on 2026-09-16 when both `context/prompts/` and that directory were
removed.

Every other row was corrected in the code on 2026-08-21 rather than recorded
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
