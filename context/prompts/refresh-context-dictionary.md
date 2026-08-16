# hoopsRN Context Dictionary — Incremental Refresh

Bring the context dictionary in `context/` back in sync with the code, re-reading only what actually changed.

This is the routine upkeep pass — run it after a batch of work lands. To build the dictionary from nothing, or when more than half the entries are stale, use `context/prompts/rebuild-context-dictionary.md` instead.

**If `context/INDEX.md` doesn't exist, stop and run the full prompt.** There's nothing to refresh incrementally.

---

## How the refresh works

Every entry declares the source paths it owns and the commit it was last verified against:

```markdown
**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/`
**Verified:** 2026-08-07 @ a1b2c3d
```

So the stale set is computable rather than guessed:

1. `git rev-parse --short HEAD` — the commit you'll stamp.
2. Read the `Scope` and `Verified` lines from every entry in `context/`.
3. For each entry: `git diff --name-only <its verified sha> HEAD` and intersect with its scope.
4. An entry with no touched files is **current** — do not reread it, do not restamp it. Leave it alone.
5. An entry with touched files is **stale** — reread only those files plus the entry, correct it, restamp it.

If an entry's `Verified` sha is missing or unresolvable (rebased away, or the entry predates the format), treat that entry as stale and reread its full scope.

Also check for **unowned changes**: any changed path matching no entry's scope. That means either a scope line needs widening or a new entry is needed — say which, and do it.

---

## The inclusion test

Applies to anything you add. **Would an agent make a wrong change without this?**

In: invariants that span files, non-obvious rationale, cross-file wiring, things that need a search to find.
Out: restatements of readable code, file/line counts, roadmaps, standard Xcode/SPM instructions.

Correcting an entry is as much about deleting what's no longer true as adding what is. Entries should not grow monotonically.

---

## Rules

1. **The code wins** over both this prompt and the existing entry text.
2. **Never touch a current entry.** An untouched `Verified` date is signal — it says nothing in that area moved. Restamping everything destroys that.
3. **Keep filenames and voice.** Update in place; don't rename, don't renumber, don't reformat an entry you're only correcting a line in.
4. **Preserve the entry format** — `Scope`, `Verified`, body, `## Invariants`, `## See also`.
5. Refresh `INDEX.md`'s date column at the end. Only add a routing-table row if a genuinely new area appeared.

---

## The dictionary

| Entry | Owns |
|---|---|
| `INDEX.md` | — (routing table + entry dates) |
| `ARCHITECTURE.md` | `hooprApp.swift`, `Services/`, `ViewModels/` |
| `DATA_MODEL.md` | `Models/` |
| `database/DATABASE_SCHEMA.md` | `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc` |
| `database/USER_PROFILE_WORKFLOW.md` | runtime auth + profile behaviour |
| `MAP_LAYER.md` | `Views/MapView.swift`, `Views/Tabs/` |
| `COURT_DATASET.md` | `Resources/`, `tools/`, `location-decoder-script/` |
| `UI_SHELL.md` | `Views/RootView.swift`, `Views/MainTabView.swift`, `Views/LoginView.swift`, `Views/Profile/`, `Support/Theme.swift` |
| `BUILD_AND_CONFIG.md` | `hoopr.xcodeproj/`, `Package.resolved`, `hooprTests/`, `hooprUITests/` |
| `GAPS.md` | — (unfinished work + doc drift) |

Entries live at the root of `context/`, except the two database entries in `context/database/`. `context/prompts/` holds these prompts and is not a dictionary entry — never stamp or diff it.

Trust each entry's own `Scope` line over this table if they differ — the entry is authoritative, this is a reminder.

---

## Invariants to re-check when their entry is stale

These are the claims most expensive to get wrong. If the entry that owns one is in the stale set, verify the invariant still holds before restamping — a violation is worth reporting to the user, not just silently rewriting.

- **Vendor boundary** (`ARCHITECTURE.md`) — `AuthService` is still the only file importing `FirebaseAuth`; `UserProfileService` the only one importing `FirebaseFirestore`. Confirm with a grep across `hoopr/`. A new Firebase import anywhere else is a design break, not a doc update.
- **Startup order** (`ARCHITECTURE.md`) — `FirebaseApp.configure()` still runs in `hooprApp.init()`, not the `AppDelegate`.
- **Mutability contract** (`database/DATABASE_SCHEMA.md`) — the `hasOnly([...])` field list in `firestore.rules` still matches the write methods on `UserProfileService`. A write method with no matching rules entry means saves fail with `permission-denied` in production until `firebase deploy --only firestore:rules` runs. Report that loudly.
- **Explicit field maps** (`DATA_MODEL.md`) — no `setData(from:)` on `UserProfile`; server timestamps stay server-assigned and `createdAt` is never clobbered.
- **UUID trigger pattern** (`MAP_LAYER.md`) — new triggers still compare on `id` alone and are still one-shot via the `Coordinator`'s last-handled ID.
- **Single profile listener** (`database/USER_PROFILE_WORKFLOW.md`) — no screen has started opening its own `users/{uid}` listener.

---

## Facts worth spot-checking cheaply

Verify these regardless of the diff — they're single greps and they're what a stale dictionary most often gets wrong:

```bash
git rev-parse --short HEAD
grep -E 'PRODUCT_BUNDLE_IDENTIFIER|IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION' hoopr.xcodeproj/project.pbxproj | sort -u
grep -A3 '"identity" : "firebase-ios-sdk"' hoopr.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
grep -rl 'import Firebase' hoopr/
python3 -c "import json;d=json.load(open('hoopr/Resources/courts.json'));print(d['version'],d['generated'],len(d['courts']),d['cities'])"
```

Last known values — correct the entry if any differ: bundle `Big-Boss-LLC.hoopr`, deployment target iOS **26.5**, Swift 5.0, firebase-ios-sdk **12.16.0**, Firebase imports confined to `AuthService.swift` + `UserProfileService.swift` (plus `FirebaseCore` in `hooprApp.swift` and `FirebaseFirestore` in `hooprTests/`), `courts.json` v1 / 2026-08-06 / **213 courts** / 6 Triangle cities.

---

## `GAPS.md`

Always revisit this entry — it has no scope to diff against, and it decays fastest.

- Delete anything that's been finished. A stale gap list is worse than none: it sends an agent to build something that already exists.
- Add gaps created by the changes you just read.
- Re-check the drift list: comments or docs contradicting the code. Known standing items — `firestore.rules` pointing at `"hoopr project info/DATABASE_SCHEMA.md"` (the folder is `context/`), and `UserProfile.homeCourtId`'s "read but never written yet" comment (both `updateHomeCourt` and the profile picker write it).

---

## Report back

Close with, in this order:

1. **Entries updated** and the one-line reason each was stale.
2. **Entries left current** — just the names.
3. **Invariant violations or unowned changes**, if any. These matter more than the doc edits and should be stated plainly, not buried.
4. **Recommendation** if more than half the entries were stale: say the dictionary has drifted far enough that a full rebuild is cheaper next time.
