# hoopsRN — Testing gaps

**Scope:** —
**Verified:** 2026-09-17 @ 8209408

What the two suites cover, what they deliberately don't, and the one recovery
path that has never been exercised for real.

`Scope: —` because this is a narrative over both test targets, which
`BUILD_AND_CONFIG.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## Where coverage stands

Two suites, in two languages, and neither can do the other's job.

- **`hooprTests` — 441 test methods across 28 suites**, confirmed by a green
  `-only-testing:hooprTests` run on 2026-09-17. Every Swift test
  targets a `nonisolated static` pure function; no test instantiates a service
  and there are no service stubs anywhere. That is a design constraint, not an
  accident: logic that can't be reached as a pure function is, in this project,
  untestable — which is why decisions keep getting lifted out into pure
  statics (`MatchRules`, `ClaimPolicy`, `SeasonGameNotifications`,
  `MatchmakingViewModel.phase`).
- **`firestore-tests/` — 102 tests**, run by `npm run test:rules` against the
  Firestore emulator. **This is the only place `firestore.rules` is evaluated
  rather than read.** A `--dry-run` compiles the file and proves nothing about
  whether a write is allowed.

`FirestoreRulesParityTests` is the third leg: it parses the rules file as text
and fails if a constant mirrored into Swift moves on only one side.

---

## What the rules suite does not cover

**Only Seasons.** `firestore-tests/` was built during the phase that needed it,
so `matchTickets`, `seasonGames` and `squads` are well covered — the claim
race, the atomic commit, the burst-rate floors, mutual confirmation — and
`games`, `friendships` and `users` have **no automated rules coverage at all**.

The `friendships` block was validated by hand once, on 2026-08-14, which proves
it was correct that day and nothing about the next edit. `games` never has
been. Backfilling those three into the existing harness is the cheapest
remaining assurance work in the project, because the harness itself was the
expensive part and it already exists.

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
