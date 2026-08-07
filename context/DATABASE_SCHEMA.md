# Hoopr — Database Schema

**Status:** `users` implemented and live. No other collections yet.
**Datastore:** Cloud Firestore (Native mode), project `hoopsrn-4f1e9`, region `nam5`.
**Rules:** `firestore.rules` at the repo root, deployed via the Firebase CLI.

Firebase Auth already provides *identity* (uid, email). The collections below are app-owned data layered on top of that identity, never a replacement for it.

For how this is wired into the app at runtime, see `USER_PROFILE_WORKFLOW.md`.

---

## `users`

One document per account. **Document ID is the Firebase Auth uid**, so a profile is addressable without a query and security rules can compare `request.auth.uid` directly against the document path.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Firebase Auth uid. Duplicates the document ID so the model decodes without optionals. |
| `userName` | string | yes | yes | Display name, 1–50 chars. **Editable and not unique** — despite the name, this is not a handle, and nothing enforces uniqueness. |
| `email` | string? | no | no | Denormalized from Auth for display only. Never a lookup key. Omitted entirely (not written as null) when Auth has none. Editing it would require a Firebase Auth re-authentication flow, so the profile screen renders it read-only. |
| `homeCourtId` | string? | no | yes | A `Court.id` from the bundled dataset. Set from the profile screen's court picker. Clearing it **deletes the field** rather than storing null. Courts don't live in Firestore, so there's no server-side reference to validate against. |
| `createdAt` | timestamp | yes | no | Server-assigned at creation. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on every write. |

### Mutability contract

`id`, `email` and `createdAt` are **write-once**. A client may only ever change `userName` and `homeCourtId` (plus the `updatedAt` bookkeeping that goes with them). This is enforced **server-side** in `firestore.rules` via `diff().affectedKeys().hasOnly([...])`, not merely by client-side discipline — a hand-crafted request that tries to rewrite `createdAt` is rejected by Firestore.

Adding a newly editable field therefore takes **two** changes: a write method on `UserProfileService`, and adding the field to `hasOnly([...])` followed by `firebase deploy --only firestore:rules`. Skipping the redeploy leaves saves failing with `permission-denied`.

### Access

- **Read:** any signed-in user. Player names must be resolvable in shared contexts (match rosters, court check-ins) in later phases.
- **Write:** only the account that owns the document.
- **Delete:** denied. Account deletion isn't a supported flow yet.

### Deliberately excluded from v1

Add later as separate, deliberate migrations — only once a feature actually needs them: `skillLevel`, `preferredPosition`, `height`, `avatarUrl`, and a separate unique `username` handle.

---

## Next collection

TBD — live check-in queues and scheduled matches, keyed to courts by `courtId` (matching `Court.id` from the bundled dataset).
