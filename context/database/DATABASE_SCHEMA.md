# Hoopr — Database Schema

**Scope:** `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc`
**Verified:** 2026-08-07 @ 2d483bb

What's stored server-side and what a client may write. `users` is implemented
and live; no other collections exist yet. Datastore is Cloud Firestore (Native
mode), project `hoopsrn-4f1e9`, region `nam5`. Rules live in `firestore.rules`
at the repo root and are deployed via the Firebase CLI.

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
| `createdAt` | timestamp | yes | no | Server-assigned at creation. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on every write. |

### Mutability contract

`id`, `email` and `createdAt` are **write-once**. A client may only ever change
`userName` and `homeCourtId` (plus the `updatedAt` bookkeeping that goes with
them). This is enforced **server-side** in `firestore.rules` via
`diff().affectedKeys().hasOnly([...])`, not merely by client-side discipline —
a hand-crafted request that tries to rewrite `createdAt` is rejected by
Firestore.

```
allow update: if isOwner()
  && request.resource.data.id == resource.data.id
  && request.resource.data.createdAt == resource.data.createdAt
  && request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['userName', 'homeCourtId', 'updatedAt'])
```

Firestore has no field-level ACLs, so field immutability is hand-built by
diffing the incoming document against the stored one.

### The two-step rule

Adding a newly editable field takes **two** changes: a write method on
`UserProfileService`, *and* adding the field to `hasOnly([...])` followed by
`firebase deploy --only firestore:rules`. Skipping the redeploy leaves saves
failing with `permission-denied` while the client code looks entirely correct.

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

`firestore.indexes.json` is empty (`indexes: []`, `fieldOverrides: []`). No
composite index is needed — every profile access is a single document read by
ID. The first query that filters or orders across `users` will need one.

### Deliberately excluded from v1

Add later as separate, deliberate migrations — only once a feature actually
needs them: `skillLevel`, `preferredPosition`, `height`, `avatarUrl`, and a
separate unique `username` handle.

---

## Invariants

- Document ID == Firebase Auth uid, and the `id` field duplicates it. Never
  generate a key.
- `id`, `email`, `createdAt` are write-once, enforced server-side.
- Every new editable field needs both a service write method and a rules
  redeploy. One without the other is a silent failure.
- Absent, never null. Clearing a field deletes it.
- Reads stay open to any signed-in user; writes stay owner-only.

## See also

- `USER_PROFILE_WORKFLOW.md` — the runtime behaviour on top of this schema.
- `../DATA_MODEL.md` — the Swift side of the contract.
- `../BUILD_AND_CONFIG.md` — the Firebase CLI surface and deploy command.
