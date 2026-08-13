# Hoopr — Context Dictionary

Working memory for an agent picking up this codebase cold. Start here, follow
the routing table to the one or two entries that own what you're changing, then
read the code.

Every entry carries a `Scope` line (the source paths it owns) and a `Verified`
stamp (date + commit sha). Scopes don't overlap; together they cover the repo.

---

## Entries

| Entry | What it answers | Verified |
|---|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the app is wired: service ownership, startup order, the Firebase vendor boundary. | 2026-08-13 @ map-tab |
| [`DATA_MODEL.md`](DATA_MODEL.md) | The domain types and their contracts — stable court IDs, the profile's write rules, derived game status, what each error case means. | 2026-08-13 @ map-tab |
| [`database/DATABASE_SCHEMA.md`](database/DATABASE_SCHEMA.md) | What's stored in Firestore and what a client may write. | 2026-08-13 @ map-tab |
| [`database/USER_PROFILE_WORKFLOW.md`](database/USER_PROFILE_WORKFLOW.md) | What happens between sign-in and a rendered profile. | 2026-08-07 @ 2d483bb |
| [`MAP_LAYER.md`](MAP_LAYER.md) | The map, its UUID trigger pattern, and the bottom-sheet state machine. | 2026-08-13 @ map-tab |
| [`COURT_DATASET.md`](COURT_DATASET.md) | Where courts come from and how to regenerate or extend them. | 2026-08-07 @ 2d483bb |
| [`UI_SHELL.md`](UI_SHELL.md) | Navigation structure, the Local Runs tab, run creation, and the visual conventions. | 2026-08-13 @ map-tab |
| [`BUILD_AND_CONFIG.md`](BUILD_AND_CONFIG.md) | Project identity, dependencies, Firebase CLI surface, real test coverage. | 2026-08-13 @ map-tab |
| [`GAPS.md`](GAPS.md) | What's unfinished, and where comments and docs contradict the code. | 2026-08-13 @ map-tab |

---

## Routing

| If you're changing… | Read first |
|---|---|
| anything touching Firebase | `ARCHITECTURE.md` (vendor boundary + startup order) |
| a stored profile field | `database/DATABASE_SCHEMA.md` + `database/USER_PROFILE_WORKFLOW.md` — it takes a service method *and* a rules redeploy |
| games, rosters, or run scheduling | `database/DATABASE_SCHEMA.md` (`games`) + `UI_SHELL.md` (Local Runs) |
| map behaviour or the bottom sheet | `MAP_LAYER.md` |
| court data, or adding a city | `COURT_DATASET.md` |
| navigation, screen presentation, or styling | `UI_SHELL.md` |
| a model field or an error case | `DATA_MODEL.md` |
| build settings, dependencies, or tests | `BUILD_AND_CONFIG.md` |
| anything at all, before trusting a code comment | `GAPS.md` |

---

## Plans

`plans/` holds designs for work that hasn't been built yet — the dictionary
describes code that exists, a plan describes code that doesn't. When a plan
ships, fold what's true into the entries above and strike it from the plan.

| Plan | Status |
|---|---|
| [`plans/LIVE_HEADCOUNT.md`](plans/LIVE_HEADCOUNT.md) | Proposed — live court occupancy via a `checkins` collection. |

---

## Refreshing this dictionary

Run `context/prompts/refresh-context-dictionary.md` for routine upkeep — it maps
changed files onto the `Scope` lines to find stale entries. Run
`context/prompts/rebuild-context-dictionary.md` to rebuild from scratch when
drift has outrun repair.

`context/prompts/` and `context/plans/` are not dictionary entries and carry no
`Scope`/`Verified` stamp.
