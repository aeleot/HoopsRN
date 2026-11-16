# hoopsRN — Friends gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

What's unfinished about `friendships` — discovery, requests, and the safety
tooling that was deferred on purpose.

`Scope: —` because this is a narrative over code `database/DATABASE_SCHEMA.md`
and `UI_SHELL.md` own. It can't be diffed, so it's re-read by hand every pass.

**Built and deployed:** the `friendships` collection and its rules, answering
and viewing requests, discovery (search by name prefix or exact ID,
`PlayerProfileSheet`, `InboxSheet` and its badge), and the friends'-public-runs
badge, and — since 2026-11-16 — blocking, reporting and a name filter.

---

## Blocking and reporting exist; what they don't cover

**Built 2026-11-16, on Spark** (App Review Guideline 1.2): Report and Block on
`PlayerProfileSheet`, Report on an opponent squad from game day, a Blocked
Players list in Profile, and a word filter on display names and squad names.
The schema and what a block does on the server are in
`../database/DATABASE_SCHEMA.md` (`blocks`, `reports`). The rules were
deployed 2026-11-16.

What's still open:

- **Nobody is told when a report arrives.** Reports are documents in the
  console and nothing else. Apple expects timely responses, so someone has to
  open `reports` on a schedule. A Cloud Function that emails on create is the
  fix, and needs Blaze (`../ROADMAP.md` §0).
- **A block is narrow.** It refuses friend requests and squad invites. It does
  not hide the blocker's profile, squads or public runs, and the two can still
  land on the same run or be matched as squads.
- **The name filter is client-side and by whole word.** A modified client can
  store any name; so can anyone creative with spelling. Rules can't hold a word
  list. Existing names were never checked — the filter only runs on a save.
- **A blocked sender's inbox badge can be stale.** `InboxButton` counts
  `FriendService.incomingRequests` directly. Blocking deletes the request, so
  the two normally agree; if that delete fails, the badge counts a request the
  inbox hides.
- **No rate limiting on requests or reports.** A modified client can still send
  requests to thousands of *different* uids, or file reports in a loop. The
  client bounds the accidental case — a 300ms search debounce, a 20-result cap,
  one write in flight. This is the longest-standing instance of the pattern in
  [`RATE_LIMITING.md`](RATE_LIMITING.md): a cooldown needs a timestamp on a
  document the write already touches, and a first-ever request to a new person
  has none. A per-account stamp would work and needs the private subcollection
  first — see [`PROFILES.md`](PROFILES.md).
- **Never run between two accounts.** The rules are raced in the emulator
  (`firestore-tests/blocks.test.mjs`); a blocked person's client showing "isn't
  accepting requests" has not been seen on a device. `LAUNCH_GAMEPLAN.md`
  FRD-05 to FRD-08.

---

## The request collision's client half has never run

The friendship rules are covered by `firestore-tests/friendships.test.mjs` on
every run, including the refused second create when two people request each
other at once. See [`TESTING.md`](TESTING.md).

**The client half has still never run:** whether `sendRequest` catches that
refusal and accepts instead of surfacing a `permission-denied`. Reaching it
needs two accounts sending to each other before either sees the other's
request. It has been reachable from the UI since discovery shipped and still hasn't been done,
and no emulator test can get to it.

---

## Still to build

- **Friends' *private* runs**, which needs a real authorization design. The
  invite decision (2026-10-08, `../database/DATABASE_SCHEMA.md`) settled the
  overlapping half and deliberately not this one: a private run opens for
  anyone holding its ID, but nothing lets a friend *find* one they weren't
  sent — `list` still ignores friendship.
- **Deferred on purpose:** push notifications on request and acceptance, unique handles, typo-tolerant search, and mutual-friend
  counts — each needs a Cloud Function or a real search index. Tracked in
  `../plans/BACKLOG.md` Track B.

---

## Live test data

A hand-seeded friendship between the developer's account and `chaseallen122`
exists in the **production** project. Delete it when it stops being useful.

---

## See also

- [`RATE_LIMITING.md`](RATE_LIMITING.md) — the request-spam gap in its wider
  context.
- [`PROFILES.md`](PROFILES.md) — the search key and the privacy question this
  feature keeps running into.
