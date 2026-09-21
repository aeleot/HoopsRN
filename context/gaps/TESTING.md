# hoopsRN — Testing gaps

**Scope:** —
**Verified:** 2026-09-20 @ b7a94ae

What the two suites cover, what they deliberately don't, and the one recovery
path that has never been exercised for real.

`Scope: —` because this is a narrative over both test targets, which
`BUILD_AND_CONFIG.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## Where coverage stands

Two suites, in two languages, and neither can do the other's job.

- **`hooprTests` — 463 test methods across 28 suites**, confirmed by a green
  `-only-testing:hooprTests` run on 2026-09-20. Every Swift test
  targets a `nonisolated static` pure function; no test instantiates a service
  and there are no service stubs anywhere. That is a design constraint, not an
  accident: logic that can't be reached as a pure function is, in this project,
  untestable — which is why decisions keep getting lifted out into pure
  statics (`MatchRules`, `ClaimPolicy`, `SeasonGameNotifications`,
  `MatchmakingViewModel.phase`, `GameService.shouldRefreshWindow`).
- **`firestore-tests/` — 141 tests across nine files**, run by
  `npm run test:rules` against the Firestore emulator. **This is the only place
  `firestore.rules` is evaluated rather than read.** A `--dry-run` compiles the
  file and proves nothing about whether a write is allowed.

`FirestoreRulesParityTests` is the third leg: it parses the rules file as text
and fails if a constant mirrored into Swift moves on only one side.

---

## All seven collections are covered now

The rules suite was Seasons-only until 2026-09-20, because that was the phase
that needed it. `games`, `friendships` and `users` — the three oldest
collections — were backfilled into the existing harness that day, 39 tests
across `games.test.mjs`, `friendships.test.mjs` and `users.test.mjs`.

What they pin, beyond the obvious per-rule cases:

- **`games`' membership diff**, the pattern `squads` and `friendships` were both
  derived from. Including the duplicate-roster hole: a set difference is only a
  faithful proxy for a stored list when the list has no duplicates, and
  `['host','me','me','me']` reads as a single addition to a set comparison.
- **`games`' two update paths** — a roster write and a completion carry disjoint
  key allowlists, so neither can smuggle the other's fields.
- **`friendships`' simultaneous-request collision**, which
  `plans/FRIENDS.md` §2 predicted and nothing had exercised: both people tap Add,
  the second `create`-shaped write lands on the existing document and falls
  through to the tighter `update` allowlist, which refuses it. That refusal is
  the correct signal, and `FriendService.sendRequest` recovers from it.
- **`users`' create allowlist**, at the point the `email` field originally
  escaped it — the allowlist reached `update` before `create`, so the very first
  write was the one that got through.

**The suite was mutation-tested on the way in.** Three rules were deliberately
weakened — the no-duplicates guard on `games`, the "requester may not accept
their own request" guard on `friendships`, and the `users` create allowlist —
and exactly the three corresponding tests failed, nothing else. `assertFails`
passes for *any* failure, including a malformed test, so a rules suite that has
never been shown to fail is not yet evidence of anything.

What remains uncovered is the **client's** half of the collision above: the
rules refuse the second create, and whether `FriendService` then accepts rather
than surfacing a `permission-denied` is a Swift concern no emulator test
reaches.

---

## The recovery path that has never really failed

`ListenerSupervisor`'s re-attach is covered by unit tests but has **never been
exercised against a live terminal error.** Doing so means deploying a broken
ruleset or dropping an index on the real project. The wiring is verified; the
end-to-end heal is not.

---

## Untested and worth it

Roughly in order of value: `RootViewModel`'s gating rule,
`FindAMatchViewModel`'s plain nearby-radius `ranked(courts:from:)` (`rankActive`
— the **Now** segment's ordering — is covered now, by `FindAMatchViewModelTests`),
`LocalRunsViewModel`'s radius/dedupe filtering, `FriendsViewModel`'s
profile-resolution cache (including the name-that-never-resolves case), and the
four `mapped(_:)` error translations.

---

## The UI target doesn't run

`hooprUITests` fails to launch its runner (`hooprUITests.xctrunner`,
`RequestDenied` from SpringBoard), so `xcodebuild test` has to be scoped with
`-only-testing:hooprTests` or the failure masks real ones.
`hooprUITests/LaunchTests.swift` is Xcode scaffold and has never carried real
coverage.

---

## See also

- `../BUILD_AND_CONFIG.md` — the commands, and why a dry-run is not a test.
- `firestore-tests/README.md` — the harness, and the JDK it needs.
- [`SEASONS.md`](SEASONS.md) — the one flow no single-client test can reach:
  two real people confirming a result to each other.
