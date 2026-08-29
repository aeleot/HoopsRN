# Firestore rules suite

The one place `firestore.rules` is **evaluated** rather than read.

```bash
npm install
npm run test:rules
```

That starts the Firestore emulator on port 8080, runs every `*.test.mjs` in
this directory against it, and shuts it down again. Nothing here talks to the
real `hoopsrn-4f1e9` project — the emulator runs under the throwaway project ID
`hoopsrn-test`, and `@firebase/rules-unit-testing` loads the ruleset off disk.

To keep an emulator running while you iterate:

```bash
npm run emulators
```

…then `node --test firestore-tests/` in another shell.

## Why this exists

Two things already check the rules, and neither one can do this job.

- `firebase deploy --only firestore:rules --dry-run` proves the file
  **compiles**. It says nothing about whether a write is allowed.
- `hooprTests/FirestoreRulesParityTests` parses this file as **text** and
  asserts that the bounds mirrored into Swift — roster sizes, the stale-claim
  window, the name length, the court-count range — still agree with it. Its own
  doc comment says what it is not: a rules evaluator.

So until this directory existed, every `allow` in `firestore.rules` had only
ever been *read*. That was tolerable while the rules only ever refused writes
the client would never make. It stopped being tolerable at `matchTickets`,
whose claim is a contested single-document transaction between two different
squads' leaders — the one place in the app where correctness depends on
Firestore's concurrency guarantees rather than on anybody's code.

`claim-race.test.mjs` races two clients for one ticket fifteen times and
asserts exactly one wins. `context/plans/SEASONS.md` §2.2 is built entirely on
that being true.

## Test runner

Node's built-in `node:test`, deliberately. This repository has no JavaScript
test culture to match, and a second test framework is a second thing to keep
working — the Swift suite is where the app's tests live. The dependency list is
`firebase-tools` (the emulator), `firebase` (the client SDK the tests drive),
and `@firebase/rules-unit-testing` (which loads the rules and mints
authenticated contexts), and nothing else.

## The other `node_modules`

`node_modules/` at the repository root already contained 27 packages before
this suite existed: `axios` and its transitive dependencies. They belong to
[`location-decoder-script/`](../location-decoder-script/), a one-off Nominatim
reverse-geocoder for the court dataset that declares `axios` in its **own**
`package.json` — somebody ran `npm install` from the repository root instead of
from that directory, and the tree landed here.

`node_modules/` is gitignored, so nothing has to be reconciled. Left alone,
they are harmless; deleted, `location-decoder-script/reverseGeocode.js` needs
its own `npm install` in its own directory before it runs again. That is the
only thing that breaks.
