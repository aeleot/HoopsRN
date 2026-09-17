// Shared setup for the Firestore rules suite.
//
// `hooprTests/FirestoreRulesParityTests` reads `firestore.rules` as text and
// checks that the constants mirrored into Swift still agree with it. That is a
// different job from this one, and it says so in its own doc comment: it is not
// a rules evaluator. **This is the evaluator.** A `firebase deploy --dry-run`
// proves the file compiles; only the emulator can prove a write is refused.
//
// Every helper here does one of two things:
//
//  - **Seeding** — writes state a client could never legally write, with rules
//    disabled, so a test can start from a claimed ticket or an accepted
//    friendship without first performing the actions that produce them.
//  - **Acting** — writes through the real rules as a named uid, so the
//    assertion is about the ruleset and nothing else.
//
// Keeping those two apart is the whole discipline: a test that seeds through
// the rules is really testing the seed, and one that acts with rules disabled
// is testing nothing at all.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, serverTimestamp, writeBatch } from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = join(here, '..');

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';

/** The command that starts what this suite needs. Named in the failure below. */
const START_COMMAND = 'npm run test:rules';

/**
 * Fails loudly when the emulator isn't there.
 *
 * A rules suite that silently passes without an emulator is worse than no rules
 * suite: it reports green for a ruleset it never evaluated, which is exactly
 * the false confidence this harness exists to remove. So the check is a hard
 * failure naming the command, not a skip.
 */
async function requireEmulator() {
  const [host, port] = EMULATOR_HOST.split(':');
  try {
    await fetch(`http://${host}:${port}/`, { signal: AbortSignal.timeout(2000) });
  } catch (error) {
    throw new Error(
      `No Firestore emulator answering on ${EMULATOR_HOST}.\n` +
        `Run the suite with:\n\n    ${START_COMMAND}\n\n` +
        '(that starts the emulator, runs these tests against it, and shuts it down again).\n' +
        `Underlying error: ${error.message}`
    );
  }
}

/**
 * A test environment loaded with **this repository's** `firestore.rules`, read
 * off disk rather than from a copy — the same `#filePath` trick the Swift
 * parity test uses, and for the same reason: a suite testing its own private
 * copy of the rules would keep passing after the deployed ones changed.
 *
 * **Every test file must pass its own `name`.** `node --test` runs files in
 * parallel processes, and the emulator is one shared server: with a single
 * project ID, one file's `clearFirestore()` deletes another file's fixtures
 * mid-run, and the damage surfaces as a rules `Null value error` on a document
 * that was seeded a moment earlier — a failure that reads as a rules bug and
 * isn't one. Projects are separate namespaces in the emulator, so a project per
 * file makes the files independent of each other and of the runner's
 * concurrency. `singleProjectMode` is off in `firebase.json` for exactly this.
 */
export async function createTestEnvironment(name) {
  await requireEmulator();

  const [host, port] = EMULATOR_HOST.split(':');

  return initializeTestEnvironment({
    projectId: `hoopsrn-test-${name}`,
    firestore: {
      rules: readFileSync(join(repositoryRoot, 'firestore.rules'), 'utf8'),
      host,
      port: Number(port),
    },
  });
}

// MARK: - Document builders
//
// Field-for-field with the Swift models, because a document shaped differently
// from what the app writes would test a ruleset nothing exercises. Each takes
// overrides so a test can bend exactly the one field it is about.

export function squadDocument(overrides = {}) {
  const id = overrides.id ?? 'squad-home';
  return {
    id,
    name: 'Rim Reapers',
    nameLower: 'rim reapers',
    leaderId: 'leader-home',
    memberIds: ['leader-home'],
    format: '3v3',
    iconKey: 'basketball.fill',
    colorKey: 'orange',
    region: 'Durham',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

export function ticketDocument(overrides = {}) {
  const squadId = overrides.squadId ?? 'squad-home';
  return {
    squadId,
    leaderId: 'leader-home',
    squadName: 'Rim Reapers',
    memberIds: ['leader-home'],
    format: '3v3',
    region: 'Durham',
    courtIds: ['court-1', 'court-2'],
    windowStart: secondsFromNow(60 * 60),
    windowEnd: secondsFromNow(60 * 60 * 5),
    wins: 0,
    losses: 0,
    status: 'open',
    createdAt: Timestamp.now(),
    expiresAt: secondsFromNow(60 * 60 * 2),
    ...overrides,
  };
}

/**
 * `SeasonGameService.commitMatch` in JavaScript — the three documents the real
 * transaction touches, in one atomic commit.
 *
 * **Atomic is the whole point, so the test has to be atomic too.** A match is
 * now made by one write that creates the `seasonGames` document and spends
 * *both* `matchTickets`, and the rules make each of the three prove the others:
 * the game demands that both tickets end this commit `matched` and pointing at
 * it, and each ticket demands that the game exist afterwards and cast it in the
 * right role. Written one at a time, every one of them is refused — which is
 * exactly what stops a squad being taken out of the pool without getting a
 * match, or getting a match without leaving the pool.
 *
 * A batched write rather than a transaction because these tests have nothing to
 * read first; `getAfter()` sees both the same way.
 *
 * The `overrides` exist so a test can break one leg on purpose — leave a ticket
 * unspent, point one at a different match — and watch the rules refuse the lot.
 */
export function commitMatch(db, game, overrides = {}) {
  const gameId = overrides.gameId ?? game.id;
  const homeSquadId = overrides.homeSquadId ?? game.homeSquadId;
  const awaySquadId = overrides.awaySquadId ?? game.awaySquadId;

  const batch = writeBatch(db);

  if (overrides.skipGame !== true) {
    batch.set(doc(db, 'seasonGames', gameId), game);
  }

  if (overrides.skipHomeTicket !== true) {
    batch.update(doc(db, 'matchTickets', homeSquadId), {
      status: 'matched',
      claimedBy: overrides.claimedBy ?? awaySquadId,
      claimedAt: serverTimestamp(),
      matchedGameId: overrides.homeMatchedGameId ?? gameId,
    });
  }

  if (overrides.skipAwayTicket !== true) {
    batch.update(doc(db, 'matchTickets', awaySquadId), {
      status: 'matched',
      matchedGameId: overrides.awayMatchedGameId ?? gameId,
    });
  }

  return batch.commit();
}

export function friendshipDocument(uidA, uidB, status = 'accepted') {
  const [first, second] = orderedPair(uidA, uidB);
  return {
    uidA: first,
    uidB: second,
    requestedBy: first,
    status,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

export function inviteDocument(squadId, uid, invitedBy) {
  return {
    squadId,
    uid,
    invitedBy,
    createdAt: Timestamp.now(),
  };
}

/** `Friendship.id(for:_:)` in Swift, and `friendshipId()` in the rules. */
export function orderedPair(uidA, uidB) {
  return uidA < uidB ? [uidA, uidB] : [uidB, uidA];
}

export function friendshipId(uidA, uidB) {
  return orderedPair(uidA, uidB).join('_');
}

export function secondsFromNow(seconds) {
  return Timestamp.fromMillis(Date.now() + seconds * 1000);
}

/**
 * Writes documents with the rules switched off.
 *
 * `docs` is a flat map of `'collection/id'` to data, which keeps a test's
 * fixture readable as a list of what exists rather than as a page of awaits.
 */
export async function seed(testEnv, docs) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const { doc, setDoc } = await import('firebase/firestore');
    for (const [path, data] of Object.entries(docs)) {
      const [collection, id] = path.split('/');
      await setDoc(doc(db, collection, id), data);
    }
  });
}

/** Reads a document past the rules, for asserting what a contested write left. */
export async function readRaw(testEnv, path) {
  let data = null;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const { doc, getDoc } = await import('firebase/firestore');
    const [collection, id] = path.split('/');
    const snapshot = await getDoc(doc(db, collection, id));
    data = snapshot.exists() ? snapshot.data() : null;
  });
  return data;
}
