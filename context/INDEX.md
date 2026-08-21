# hoopsRN — Context Dictionary

Working memory for an agent picking up this codebase cold. Start here, follow
the routing table to the one or two entries that own what you're changing, then
read the code.

Every entry carries a `Scope` line (the source paths it owns) and a `Verified`
stamp (date + **commit sha**, never a branch name — a branch moves and the stamp
stops meaning anything). Scopes don't overlap, and together they cover every
source path in the repo.

Three entries own no paths and say so with `Scope: —`: `GAPS.md`,
`PRODUCT_OVERVIEW.md`, and `database/USER_PROFILE_WORKFLOW.md`. All three are
cross-cutting narratives over code other entries own, so they can't be diffed —
the drift check lists them under "always revisit" and they're re-read by hand
every pass.

---

## Entries

| Entry | What it answers | Verified |
|---|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the app is wired: service ownership, startup order, the Firebase vendor boundary, listener recovery. | 2026-08-21 @ 9a81cc2 |
| [`DATA_MODEL.md`](DATA_MODEL.md) | The domain types and their contracts — stable court IDs, the profile's write rules, derived game status, what each error case means. | 2026-08-21 @ 9a81cc2 |
| [`database/DATABASE_SCHEMA.md`](database/DATABASE_SCHEMA.md) | What's stored in Firestore and what a client may write, across all three collections. | 2026-08-21 @ 9a81cc2 |
| [`database/USER_PROFILE_WORKFLOW.md`](database/USER_PROFILE_WORKFLOW.md) | What happens between sign-in and a rendered profile, including the search-key backfill. | 2026-08-21 @ 9a81cc2 |
| [`MAP_LAYER.md`](MAP_LAYER.md) | The map, its UUID trigger pattern, the north bias, and the bottom sheet's detent machine. | 2026-08-21 @ 9a81cc2 |
| [`COURT_DATASET.md`](COURT_DATASET.md) | Where courts come from and how to regenerate or extend them. | 2026-08-21 @ 9a81cc2 |
| [`UI_SHELL.md`](UI_SHELL.md) | Navigation structure, the Local Runs tab, the profile and its Friends pane, run creation, and the visual conventions. | 2026-08-21 @ 9a81cc2 |
| [`BUILD_AND_CONFIG.md`](BUILD_AND_CONFIG.md) | Project identity, dependencies, the Firebase CLI surface, repo tooling, real test coverage. | 2026-08-21 @ 9a81cc2 |
| [`GAPS.md`](GAPS.md) | What's unfinished, and where comments and docs contradict the code. | 2026-08-21 @ 9a81cc2 |
| [`PRODUCT_OVERVIEW.md`](PRODUCT_OVERVIEW.md) | **Business-facing.** What users can do today, what the app guarantees on security, accessibility and coverage, and what's planned. | 2026-08-21 @ 9a81cc2 |

---

## Routing

| If you're changing… | Read first |
|---|---|
| anything touching Firebase | `ARCHITECTURE.md` (vendor boundary + startup order) |
| a stored profile field | `database/DATABASE_SCHEMA.md` + `database/USER_PROFILE_WORKFLOW.md` — it takes a service method *and* a rules redeploy |
| games, rosters, or run scheduling | `database/DATABASE_SCHEMA.md` (`games`) + `UI_SHELL.md` (Local Runs) |
| friendships, requests, or player search | `database/DATABASE_SCHEMA.md` (`friendships`) + `UI_SHELL.md` (the profile's Friends pane) |
| a snapshot listener, or an error message | `ARCHITECTURE.md` (`ListenerSupervisor`, and the read/write split on `permission-denied`) |
| map behaviour or the bottom sheet | `MAP_LAYER.md` |
| court data, or adding a city | `COURT_DATASET.md` |
| navigation, screen presentation, or styling | `UI_SHELL.md` |
| a model field or an error case | `DATA_MODEL.md` |
| build settings, dependencies, or tests | `BUILD_AND_CONFIG.md` |
| anything at all, before trusting a code comment | `GAPS.md` |
| explaining the product to someone, or scoping a roadmap | `PRODUCT_OVERVIEW.md` |

---

## Plans

`plans/` holds designs for work that hasn't been built yet — the dictionary
describes code that exists, a plan describes code that doesn't. When a plan
ships, fold what's true into the entries above and strike it from the plan.

| Plan | Status |
|---|---|
| [`plans/LIVE_HEADCOUNT.md`](plans/LIVE_HEADCOUNT.md) | Proposed — live court occupancy via a `checkins` collection. |
| [`plans/FRIENDS.md`](plans/FRIENDS.md) | **Partly shipped** — the `friendships` backend (Phase 1), the Friends UI (Phase 2), and search, public profiles and the inbox (Phase 3) are built and folded into the entries above. The friends'-public-runs badge (Phase 4) is still a proposal. |
| [`plans/SCALE_UP.md`](plans/SCALE_UP.md) | Proposed — the multi-city scaling roadmap: the global public-games query fix, court-dataset delivery for many cities, and the sequencing of every other pending feature/gap around them. |
| [`plans/BACKLOG.md`](plans/BACKLOG.md) | Proposed — medium-to-large enhancement stories in four tracks: the Queue Up matchmaking feature, the friends system, UI depth, and correctness/standards. Its D1 records verified drift in the entries above. |

---

## Refreshing this dictionary

Run `python3 tools/check_context_drift.py` **first**, always. It parses every
entry's `Scope`/`Verified` header, diffs the owned paths against the working
tree — uncommitted work included, not just the last commit — and prints which
entries are stale, unresolvable, or current, plus any changed file that matches
no entry's scope at all. Feed its output straight into the refresh rather than
re-deriving staleness by hand, and don't restamp an entry it calls current: an
untouched stamp is the signal that nothing in that area moved.

Then run `context/prompts/refresh-context-dictionary.md` for routine upkeep, or
`context/prompts/rebuild-context-dictionary.md` when more than half the entries
are stale and incremental repair has stopped being worth it.

`context/prompts/` and `context/plans/` are not dictionary entries and carry no
`Scope`/`Verified` stamp.
