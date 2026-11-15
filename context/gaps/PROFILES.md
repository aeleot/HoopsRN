# hoopsRN — Profile and account gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

What's unfinished about `users/{uid}` and the account behind it — the search
key, what a profile leaks, and what sign-in still can't do.

`Scope: —` because this is a narrative over code `DATA_MODEL.md`,
`database/DATABASE_SCHEMA.md` and `database/USER_PROFILE_WORKFLOW.md` own. It
can't be diffed, so it's re-read by hand every pass.

---

## The search key completes one account at a time

**Name search can't see an account until its owner has opened the app since the
`userNameLower` backfill shipped.** `UserProfileService` writes the missing
search key on the owner's own client, because the update rule is owner-only and
there's no Cloud Function to do it server-side — so the migration completes one
account at a time, as people launch the app. Anyone who hasn't is findable by
user ID but not by name.

Nothing more can be done about this from the client; a real backfill needs an
admin-SDK script run against the project. Don't rediscover this as "search is
broken" — it is search working exactly as a client-side migration can.

---

## A chosen subset is not privacy

**`users` documents are readable whole by any signed-in account.**
`PlayerProfileSheet` renders name, home court and joined, and deliberately
leaves `favoriteCourtIds` and `preferredRadius` off — but leaving a field out of
a *view* doesn't take it off the wire. Both are still readable by anyone signed
in, and `homeCourtId` plus `favoriteCourtIds` together are a location pattern
attached to a named person.

The real fix is the owner-only `users/{uid}/private/…` subcollection named in
`database/DATABASE_SCHEMA.md`. It hasn't been built, and it's the same
subcollection Phase 5's blocking list would need regardless.

**This is also where any future rate-limit stamp belongs.** The burst-rate
floors added to `matchTickets` and `seasonGames` (see
`database/DATABASE_SCHEMA.md`) compare against timestamps that were already on
the documents being written. A floor on *squad creation* has no such document —
it would need a per-account stamp, and putting one on a world-readable profile
would leak activity timing to every signed-in user. It belongs in the private
subcollection, which is a reason to build that before reaching for the stamp.

---

## What sign-in still can't do

- **Account deletion leaves two kinds of document behind, on purpose**
  (shipped 2026-11-14 — `AccountDeletionPlan`, `DeleteAccountViewModel`). The
  deleted uid stays in `seasonGames` (undeletable by design) and on the roster
  of **completed** runs (the roster rule only admits changes to a live run, and
  deleting a completed run the account hosted would take it out of everyone
  else's history). It is an opaque ID that no longer resolves to a profile.
  A run the account was on that is `in_progress` is also left as it was.
- **Account deletion is client-driven, so it can stop halfway.** Spark has no
  Cloud Functions; the phone makes every write. Each step is safe to repeat and
  the sheet says "tap Delete to pick up where it stopped", but someone who
  quits mid-way and never returns keeps an account with some of its data gone.
  The *Delete User Data* extension would close this on Blaze.
- **Deletion re-authenticates by password only.** Correct today — email and
  password is the only provider — and wrong the day Google sign-in lands: that
  account has no password to type. `AuthService.reauthenticate` needs a
  per-provider path before then.
- **The deletion flow has never run end to end.** Its plan and wording are
  unit-tested and the `users` delete rule passes its emulator tests (150/150,
  2026-11-14, deployed the same day), but no account has actually been deleted
  with it.
- **No social login.** Email and password only.
- **The password reset uses Firebase's default hosted page.** No
  `ActionCodeSettings`, so the link doesn't come back into the app, and the
  email is Firebase's default template with the project's name on it. Both are
  console/config work rather than code. The app is also never told when the link
  is used, so nothing in it reflects "password last changed".
- **Sign-up has no verification step at all** — no email confirmation, no
  CAPTCHA, no App Check. Accounts are free and unlimited, which is what caps the
  value of every per-account limit elsewhere in the app: a limit scoped to a uid
  is a speed bump when a fresh uid costs nothing. See
  [`RATE_LIMITING.md`](RATE_LIMITING.md).

---

## See also

- `../database/USER_PROFILE_WORKFLOW.md` — what happens between sign-in and a
  rendered profile, including the backfill above.
- `../database/DATABASE_SCHEMA.md` — the `users` key allowlists, and why they
  are what keeps a world-readable document safe.
- [`FRIENDS.md`](FRIENDS.md) — discovery and requests, which is what makes a
  profile visible to anyone in the first place.
