# Hoopr — Database Schema

**Scope:** `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc`
**Verified:** 2026-08-13 @ map-tab

What's stored server-side and what a client may write. Two collections are
live: `users` (one owner per document) and `games` (the first shared,
multi-user state). Datastore is Cloud Firestore (Native mode), project
`hoopsrn-4f1e9`, region `nam5`. Rules live in `firestore.rules` at the repo
root and are deployed via the Firebase CLI.

Firebase Auth already provides *identity* (uid, email). The collection below is
app-owned data layered on top of that identity, never a replacement for it.

For how this is wired into the app at runtime, see `USER_PROFILE_WORKFLOW.md`.

---

## `users`

One document per account. **Document ID is the Firebase Auth uid**, so a profile
is addressable without a query and security rules can compare `request.auth.uid`
directly against the document path.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Firebase Auth uid. Duplicates the document ID so the model decodes without optionals. |
| `userName` | string | yes | yes | Display name, 1–50 chars. **Editable and not unique** — despite the name, this is not a handle, and nothing enforces uniqueness. |
| `email` | string? | no | no | Denormalized from Auth for display only. Never a lookup key. Omitted entirely (not written as null) when Auth has none. Editing it would require a Firebase Auth re-authentication flow, so the profile screen renders it read-only. |
| `homeCourtId` | string? | no | yes | A `Court.id` from the bundled dataset. Set from the profile screen's court picker. Clearing it **deletes the field** rather than storing null. Courts don't live in Firestore, so there's no server-side reference to validate against — a stale ID resolves to "Unknown court" in the UI. |
| `favoriteCourtIds` | array\<string\>? | no | yes | Starred courts, written with `arrayUnion`/`arrayRemove` so two devices can't clobber each other. Absent on profiles provisioned before favourites existed. Stored inline rather than as a subcollection so it rides the profile listener that's already open. |
| `preferredRadius` | number? | no | yes | Search radius in miles for the nearby courts list. Set from the profile screen's slider. Rules bound **writes** to 1–50, but say nothing about rows already stored — the client coerces anything out of range back to the 5-mile default (see `../DATA_MODEL.md`). A `0` seeded by hand in the console reads as "unset", not as a zero-mile search. |
| `createdAt` | timestamp | yes | no | Server-assigned at creation. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on every write. |

### Mutability contract

`id`, `email` and `createdAt` are **write-once**. A client may only ever change
`userName`, `homeCourtId`, `preferredRadius`, and `favoriteCourtIds` (plus the
`updatedAt` bookkeeping that goes with them). This is enforced **server-side** in `firestore.rules` via
`diff().affectedKeys().hasOnly([...])`, not merely by client-side discipline —
a hand-crafted request that tries to rewrite `createdAt` is rejected by
Firestore.

```
allow update: if isOwner()
  && request.resource.data.id == resource.data.id
  && request.resource.data.createdAt == resource.data.createdAt
  && request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['userName', 'homeCourtId', 'preferredRadius',
                 'favoriteCourtIds', 'updatedAt'])
```

Firestore has no field-level ACLs, so field immutability is hand-built by
diffing the incoming document against the stored one.

### The two-step rule

Adding a newly editable field takes **two** changes: a write method on
`UserProfileService`, *and* adding the field to `hasOnly([...])` followed by
`firebase deploy --only firestore:rules`. Skipping the redeploy leaves saves
failing with `permission-denied` while the client code looks entirely correct.

**`favoriteCourtIds` shipped without step two and stayed broken**, which is what
this warning is for. The service method and the star UI both landed; the rule
still listed only three fields, so every star tap was rejected server-side. It
was invisible because `toggleFavorite` is optimistic — the star fills in, the
write fails, and the profile listener quietly reverts it. Found in the device
log (`Profile error while saving your favorites: permissionDenied`), not on
screen. If you add a field and it "works" locally, check the log before
believing it.

### Absent vs. null

Absence is the convention, never an explicit null. Clearing a home court writes
`FieldValue.delete()`; provisioning omits `email` when Auth has none. The rules
follow suit — the `homeCourtId` type check is written to tolerate the field
being absent:

```
&& (!('homeCourtId' in request.resource.data)
    || request.resource.data.homeCourtId is string)
```

### Access

- **Read:** any signed-in user. Player names must be resolvable in shared
  contexts (match rosters, court check-ins) in later phases.
- **Create:** owner only, and the document must carry `id == uid` with a
  1–50 character `userName`.
- **Update:** owner only, under the mutability contract above.
- **Delete:** denied outright. Account deletion isn't a supported flow yet.

### Indexes

No composite index is needed for `users` — every profile access is a single
document read by ID. The first query that filters or orders across `users` will
need one. The two indexes that *do* exist belong to `games`, below.

### Deliberately excluded from v1

Add later as separate, deliberate migrations — only once a feature actually
needs them: `skillLevel`, `preferredPosition`, `height`, `avatarUrl`, and a
separate unique `username` handle.

---

## `games`

One document per scheduled run. **This is the first collection more than one
person writes to**, and the mutability contract is what makes that safe: the
host authors the run, and everyone else may only ever move *themselves* between
its two rosters.

Unlike `users`, the document ID is **generated by Firestore**. There's no
natural key — a person can host many runs — so `id` mirrors the generated ID
purely so the Swift model decodes without a `@DocumentID` wrapper, which would
drag a Firebase type across the vendor boundary into `Models/`.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Mirrors the document ID. Rules pin `id == gameId` at creation. |
| `hostId` | string | yes | no | Organizer's uid. Always present in `playerIds` — enforced server-side, so a run can't outlive its host leaving it. |
| `courtId` | string | yes | no | A `Court.id` from the bundled dataset. Courts aren't in Firestore, so there's nothing to validate against — same caveat as `homeCourtId`. A stale ID renders "Unknown court". |
| `scheduledTime` | timestamp | yes | no | Client-supplied, bounded server-side to `(now, now + 30d)`. |
| `isPublic` | bool | yes | no | `true` = discoverable. `false` = visible only to people already on a roster. |
| `maxPlayers` | int | yes | no | 2–30, bounded by the rules. |
| `status` | string | yes | yes | `open` \| `full` \| `in_progress` \| `completed`. **Derived, never chosen** — see below. |
| `playerIds` | array\<string\> | yes | yes | Confirmed players, host included. Never longer than `maxPlayers`. |
| `queuedPlayerIds` | array\<string\> | yes | yes | Waitlist. Always written as `[]` rather than omitted — the update rule diffs both arrays together, and an absent field would make that arithmetic conditional for no gain. |
| `createdAt` | timestamp | yes | no | Pinned to `request.time`. |
| `updatedAt` | timestamp | yes | yes | Pinned to `request.time` on every write. |

### `status` is derived, not chosen

The rules recompute it from the roster that ships in the same request:

```
request.resource.data.status ==
  (request.resource.data.playerIds.size() >= request.resource.data.maxPlayers
     ? 'full' : 'open')
```

So `open`/`full` can't drift from `playerIds.count`, and a client that computes
it differently is rejected rather than quietly storing a contradiction.
`Game.status(playerCount:maxPlayers:)` is the client's single copy of the same
rule — **changing one without the other turns every write into a
`permission-denied`.**

That's now caught before it ships. `hooprTests/FirestoreRulesParityTests` parses
`firestore.rules`, extracts the comparison and the two status literals out of
`statusMatchesRoster()`, and runs the reconstructed rule against
`Game.status(playerCount:maxPlayers:)` over every roster in
`Game.maxPlayersRange` — plus a couple past the cap, where a `>` / `>=` swap
hides. The same file pins the roster bounds, the scheduling window, the radius
range and the `userName` cap. **Change a bound on one side and a test fails
naming both sides.** It is not a rules evaluator; it only proves the shared
constants still agree.

`in_progress` and `completed` are declared by the schema but **nothing writes
them yet**: the update rule only ever admits `open`/`full`. A run simply ages
out of both lists once it's past its visibility grace window (3h after tip-off).

### The membership diff

The load-bearing check on update. Both rosters are unioned into a set before
and after, and the symmetric difference must contain nothing but the caller:

```
members(after).difference(members(before)).hasOnly([request.auth.uid])
&& members(before).difference(members(after)).hasOnly([request.auth.uid])
```

Two consequences worth stating plainly:

- **A freed slot is not handed to the first waitlisted player.** Promotion means
  writing *someone else's* uid, which this rejects by design. It needs a host
  action or a Cloud Function; neither exists yet.
- **Invite-only runs currently hold only their host.** Nobody else can read
  them, so nobody else can join. Invites are the missing half of that feature.

Everything describing the run itself — court, time, visibility, size, host — is
immutable, so there is no "edit a run" path to secure.

### Access

- **Read:** any signed-in user, for a run that is `isPublic` **or** one they're
  already on. The two client queries are constrained to exactly those shapes, so
  each returns only documents the rule already admits.
- **Create:** the host only, as the sole player, with both timestamps pinned to
  `request.time` and the schedule inside its window.
- **Update:** any signed-in user, restricted to
  `['playerIds', 'queuedPlayerIds', 'status', 'updatedAt']` under the membership
  diff above.
- **Delete:** the host only. **Deliberately unlike `users`**, where deletion is
  denied outright — cancelling a run is a first-class action, whereas account
  deletion is an unsupported flow.

### Indexes

Two composite indexes, the first entries `firestore.indexes.json` has ever
held. Each backs one listener, and each is an equality-or-array-contains plus a
range on `scheduledTime`:

| Query | Index |
|---|---|
| `playerIds array-contains uid`, `scheduledTime > cutoff`, ordered | `(playerIds CONTAINS, scheduledTime ASC)` |
| `isPublic == true`, `scheduledTime > cutoff`, ordered | `(isPublic ASC, scheduledTime ASC)` |

**Radius is not in either query.** Courts live in the bundled dataset, not in
Firestore, so there are no coordinates server-side to filter on — the distance
filter is a client-side join in `LocalRunsViewModel`. Doing it server-side would
mean geohashing every run on write.

Deploy both alongside the rules:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### Deliberately excluded from v1

Invites (the other half of invite-only), waitlist promotion, host-run controls
for `in_progress`/`completed`, recurring runs, and any per-run chat.

---

## Invariants

- Document ID == Firebase Auth uid for `users`, and the `id` field duplicates
  it. Never generate a key for a profile. `games` is the exception: Firestore
  generates the ID and `id` mirrors it.
- `Game.status` is derived from the roster on both sides of the wire. The
  client helper and the rules expression must stay identical.
- A client may only ever add or remove **itself** from a run's rosters.
- `queuedPlayerIds` is always written, `[]` when empty — the one place the
  "absent, never null" convention is deliberately not applied.
- `id`, `email`, `createdAt` are write-once, enforced server-side.
- Every new editable field needs both a service write method and a rules
  redeploy. One without the other is a silent failure.
- Absent, never null. Clearing a field deletes it.
- Reads stay open to any signed-in user; writes stay owner-only.

## See also

- `USER_PROFILE_WORKFLOW.md` — the runtime behaviour on top of this schema.
- `../DATA_MODEL.md` — the Swift side of the contract.
- `../BUILD_AND_CONFIG.md` — the Firebase CLI surface and deploy command.
