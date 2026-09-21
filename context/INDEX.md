# hoopsRN — Context Dictionary

Working memory for an agent picking up this codebase cold. **Start with the
routing table below**, read the one or two entries that own what you're
changing, then read the code.

Everything in `context/` is one of three kinds of thing, and keeping them apart
is what stops this folder becoming a pile:

| Kind | Answers | Where |
|---|---|---|
| **Dictionary entry** | How the thing that exists works | `*.md`, `database/` |
| **Gap** | What's wrong, missing, or unverified about it | [`gaps/`](gaps/) |
| **Plan** | How something that *doesn't* exist would work | [`plans/`](plans/) |

A subject appears in exactly one of the three. When a plan ships, fold what's
true into the entries and strike it from the plan; when a gap closes, delete
it rather than striking it through.

---

## Routing — if you're changing…

| …this | Read first |
|---|---|
| anything touching Firebase | `ARCHITECTURE.md` — the vendor boundary and startup order |
| a snapshot listener, or an error message | `ARCHITECTURE.md` — `ListenerSupervisor`, and the read/write split on `permission-denied` |
| a stored field, or any write rule | `database/DATABASE_SCHEMA.md` — **and expect a rules redeploy**, not just a service method |
| a profile field, or sign-in | `database/DATABASE_SCHEMA.md` + `database/USER_PROFILE_WORKFLOW.md` |
| games, rosters, or run scheduling | `database/DATABASE_SCHEMA.md` (`games`) + `UI_SHELL.md` (Local Runs) |
| friendships, requests, or player search | `database/DATABASE_SCHEMA.md` (`friendships`) + `UI_SHELL.md` |
| squads, matchmaking, game day, results | `gaps/SEASONS.md` **first** — several Seasons behaviours are capped or unverified in ways the code doesn't show |
| a model field or an error case | `DATA_MODEL.md` |
| map behaviour or the bottom sheet | `MAP_LAYER.md` |
| court data, or adding a city | `COURT_DATASET.md` |
| navigation, screen presentation, styling | `UI_SHELL.md` |
| build settings, dependencies, tests | `BUILD_AND_CONFIG.md` |
| **anything at all, before trusting a code comment** | [`GAPS.md`](GAPS.md) |
| explaining the product to someone | `PRODUCT_OVERVIEW.md` |
| deciding what to work on next | [`ROADMAP.md`](ROADMAP.md) |

---

## The dictionary

Entries that describe **code that exists today**.

### Owns source paths — drift-checked automatically

Each carries a `Scope` line listing the paths it owns and a `Verified` stamp
(date + commit sha). Scopes don't overlap, and together they cover every source
path in the repo.

| Entry | What it answers |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the app is wired: service ownership, startup order, the Firebase vendor boundary, listener recovery, and the one write that spans two collections. |
| [`DATA_MODEL.md`](DATA_MODEL.md) | The domain types and their contracts — stable court IDs, the profile's write rules, derived game status, what each error case means. |
| [`database/DATABASE_SCHEMA.md`](database/DATABASE_SCHEMA.md) | What's stored in Firestore and what a client may write, across all **seven** collections — plus the rate-limit floors and why they're cooldowns rather than quotas. |
| [`MAP_LAYER.md`](MAP_LAYER.md) | The map, its UUID trigger pattern, the north bias, and the pins' heat-map colouring. |
| [`COURT_DATASET.md`](COURT_DATASET.md) | Where courts come from and how to regenerate or extend them. |
| [`UI_SHELL.md`](UI_SHELL.md) | Navigation structure, the tabs, run creation, the Seasons card's four states, and the visual conventions. |
| [`BUILD_AND_CONFIG.md`](BUILD_AND_CONFIG.md) | Project identity, dependencies, the Firebase CLI surface, repo tooling, real test coverage. |

### Owns no paths — re-read by hand

These are cross-cutting narratives over code the entries above own, so they
can't be diffed. They declare `Scope: —` and the drift check lists them under
*always revisit*.

| Entry | What it answers |
|---|---|
| [`PRODUCT_OVERVIEW.md`](PRODUCT_OVERVIEW.md) | **Business-facing.** What users can do today, what the app guarantees, and what's deliberately not built. The document to hand someone who won't read the code. |
| [`database/USER_PROFILE_WORKFLOW.md`](database/USER_PROFILE_WORKFLOW.md) | What happens between sign-in and a rendered profile, including the search-key backfill. |
| [`GAPS.md`](GAPS.md) | Router into `gaps/`, plus the known-drift table. |
| [`ROADMAP.md`](ROADMAP.md) | What to do next, in order, and the one infrastructure decision that gates six of them. |

---

## Gaps

What's wrong with what exists. [`GAPS.md`](GAPS.md) routes; the files live in
[`gaps/`](gaps/) and are listed there rather than duplicated here.

**`gaps/` is flat on purpose.** `tools/check_context_drift.py` scans
`context/*.md` plus the directories named explicitly in its `entry_files()` —
currently `database` and `gaps`. **A file in a subdirectory that function
doesn't know about is silently unchecked forever**, which is worse than a
typo'd scope. Adding a nesting level means editing that function too.

---

## Plans

Designs for work that hasn't been built. A plan describes code that doesn't
exist; the dictionary describes code that does.

| Plan | Status |
|---|---|
| [`plans/SEASONS.md`](plans/SEASONS.md) | **Shipped.** All eight phases built and folded into the entries; §6 records where each went. Kept for §0 (why there is no server-side matchmaker), §7 (what's deliberately out of reach) and §8 (live risks). |
| [`plans/FRIENDS.md`](plans/FRIENDS.md) | **Partly shipped.** Phases 1–4 (backend, UI, discovery, the friends'-public-runs badge) are built. Only Phase 5 (safety tooling) is still a proposal, and it was deferred on purpose. |
| [`plans/STATS_CARD.md`](plans/STATS_CARD.md) | **Partly shipped.** Phases 1–3 built; the card stays empty until something writes `status: "completed"` — see `gaps/GAMES.md`. |
| [`plans/APP_SHELL_AND_HOME.md`](plans/APP_SHELL_AND_HOME.md) | **Shipped.** Bottom tab bar, Home tab, inline court search. Its §5 records the colour work a native tab bar forced — now tracked in `gaps/ACCESSIBILITY.md`. |
| [`plans/LIVE_HEADCOUNT.md`](plans/LIVE_HEADCOUNT.md) | Proposed — live court occupancy via a `checkins` collection. |
| [`plans/SCALE_UP.md`](plans/SCALE_UP.md) | Proposed — multi-city scaling: the global public-games query fix, court-dataset delivery, and the sequencing around them. |
| [`plans/BACKLOG.md`](plans/BACKLOG.md) | Proposed — enhancement stories across four tracks. Its Queue Up track shipped 2026-09-16; the rest stands. |
| [`plans/LAUNCH_READINESS.md`](plans/LAUNCH_READINESS.md) | **Partly shipped.** The 2026-09-20 staff audit, ten items, none of them code defects. Items 1, 3, 6 and 10 landed the same day — **no submission blockers remain**. App Check (§2) is the highest-value item left. Its correction note records an availability claim the audit got wrong. |

---

## Keeping this honest

**Run the drift check first, always:**

```bash
python3 tools/check_context_drift.py
```

It parses every entry's `Scope`/`Verified` header, diffs the owned paths
against the working tree — **uncommitted work included** — and prints what's
stale, unresolvable, always-revisit, or current, plus any changed file matching
no entry's scope at all. That last one is a live scope gap, not something to
shrug off.

Then:

1. For each **stale** entry, reread only the files it named plus the entry's
   own text. Correct it, then restamp with `git rev-parse --short HEAD` —
   **never a branch or tag name.** A branch ref moves every time someone
   pushes, so `@ some-branch` silently stops meaning "verified at this exact
   commit", and this whole mechanism depends on the stamp being a fixed point.
2. Leave every entry it calls **current** untouched. An untouched stamp is the
   signal that nothing in that area moved — restamping it destroys that signal.
3. Re-read the **always revisit** entries by hand. They own no paths, so
   nothing can tell you when they rot.

**The stamp lives in the entry's own header and nowhere else.** This page
deliberately does not repeat it: it was duplicated here until 2026-09-16, and
six of eleven copies had drifted from the files they described, because nothing
kept them in sync. One copy, in the file the tool actually reads.
