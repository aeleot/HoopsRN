// **The claim race** — the one guarantee the entire matchmaker rests on.
//
// `context/plans/SEASONS.md` §2.2: there is no server, so matchmaking is pull
// with a lock. Every queued client watches the same pool and the winner of a
// one-document race gets to create the match. That inversion only works if
// Firestore really does serialize contested single-document transactions such
// that **exactly one** claimer wins — and until this file existed, that was a
// sentence in a design document.
//
// A race that has never been raced is a claim, not a result. So this runs it,
// repeatedly, because a race that passes once passed by luck.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { doc, runTransaction, serverTimestamp } from 'firebase/firestore';

import {
  createTestEnvironment,
  readRaw,
  seed,
  secondsFromNow,
  squadDocument,
  ticketDocument,
} from './harness.mjs';

/** How many times the race is run. Enough that a lucky pass is unlikely. */
const ROUNDS = 15;

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('claim-race');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/**
 * `MatchmakingService.claim` in JavaScript, condition for condition.
 *
 * The guards inside the transaction are the point: the scan that produced the
 * candidate ran against a pool snapshot that may be seconds stale, and the
 * transaction's own read is the only view of the ticket guaranteed current.
 * A loser of the race re-reads on Firestore's retry, fails this guard, and
 * throws — which is what turns a contended write into a clean "claim lost"
 * rather than a corrupted document.
 */
function claim(db, ticketSquadId, claimingSquadId) {
  const reference = doc(db, 'matchTickets', ticketSquadId);

  return runTransaction(db, async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists()) throw new Error('ticketNotFound');

    const data = snapshot.data();
    const now = Date.now();

    if (data.expiresAt.toMillis() <= now) throw new Error('claimLost');

    const stale =
      data.status === 'claimed' &&
      data.claimedAt != null &&
      now - data.claimedAt.toMillis() > 90_000;

    if (data.status !== 'open' && !stale) throw new Error('claimLost');

    transaction.update(reference, {
      status: 'claimed',
      claimedBy: claimingSquadId,
      claimedAt: serverTimestamp(),
    });
  });
}

/** The three squads and the one contested ticket every round starts from. */
async function seedPool() {
  await seed(testEnv, {
    'squads/squad-home': squadDocument({
      id: 'squad-home',
      leaderId: 'leader-home',
      memberIds: ['leader-home'],
    }),
    'squads/squad-b': squadDocument({
      id: 'squad-b',
      name: 'Court Vision',
      nameLower: 'court vision',
      leaderId: 'leader-b',
      memberIds: ['leader-b'],
    }),
    'squads/squad-c': squadDocument({
      id: 'squad-c',
      name: 'Baseline',
      nameLower: 'baseline',
      leaderId: 'leader-c',
      memberIds: ['leader-c'],
    }),
    'matchTickets/squad-home': ticketDocument({ squadId: 'squad-home' }),
  });
}

test('two concurrent claims on one ticket produce exactly one winner', async () => {
  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  const dbC = testEnv.authenticatedContext('leader-c').firestore();

  for (let round = 1; round <= ROUNDS; round += 1) {
    await testEnv.clearFirestore();
    await seedPool();

    const results = await Promise.allSettled([
      claim(dbB, 'squad-home', 'squad-b'),
      claim(dbC, 'squad-home', 'squad-c'),
    ]);

    const winners = results.filter((result) => result.status === 'fulfilled');
    const losers = results.filter((result) => result.status === 'rejected');

    assert.equal(
      winners.length,
      1,
      `round ${round}: expected exactly one winner, got ${winners.length}. ` +
        `Rejections: ${losers.map((l) => l.reason?.message ?? l.reason).join(' | ')}`
    );

    // The loser gets a transaction failure, not a half-written document.
    const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
    assert.equal(ticket.status, 'claimed', `round ${round}: ticket status`);
    assert.ok(
      ticket.claimedBy === 'squad-b' || ticket.claimedBy === 'squad-c',
      `round ${round}: claimedBy was ${ticket.claimedBy}`
    );
    assert.ok(ticket.claimedAt != null, `round ${round}: claimedAt was never stamped`);

    // Nothing else moved. The claim's affectedKeys allowlist is three fields
    // wide, and a claim that also rewrote the pool fields would be a claim that
    // could rewrite `memberIds` — the field the no-shared-players rule reads.
    assert.deepEqual(ticket.memberIds, ['leader-home'], `round ${round}: memberIds moved`);
    assert.equal(ticket.squadName, 'Rim Reapers', `round ${round}: squadName moved`);
    assert.equal(ticket.leaderId, 'leader-home', `round ${round}: leaderId moved`);
  }
});

test('the loser of a race fails with claimLost rather than writing over the winner', async () => {
  await seedPool();

  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  const dbC = testEnv.authenticatedContext('leader-c').firestore();

  await claim(dbB, 'squad-home', 'squad-b');

  // Sequential, not concurrent: this is the *second* squad arriving after the
  // claim has already landed, which is the common case in a live pool — the
  // pool snapshot is a second old and the ticket has moved on.
  await assert.rejects(
    () => claim(dbC, 'squad-home', 'squad-c'),
    /claimLost/,
    'a claim against an already-claimed ticket must fail the in-transaction guard'
  );

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.claimedBy, 'squad-b');
});

test('a fresh claim is refused by the rules even if a client skips its own guard', async () => {
  // The Swift guard is a courtesy to the pool, not the enforcement. A modified
  // client that dropped it must still be refused server-side, or the 90-second
  // stale window would be advisory.
  await seedPool();
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      squadId: 'squad-home',
      status: 'claimed',
      claimedBy: 'squad-b',
      claimedAt: secondsFromNow(-5),
    }),
  });

  const dbC = testEnv.authenticatedContext('leader-c').firestore();
  const reference = doc(dbC, 'matchTickets', 'squad-home');

  await assert.rejects(
    () =>
      runTransaction(dbC, async (transaction) => {
        await transaction.get(reference);
        transaction.update(reference, {
          status: 'claimed',
          claimedBy: 'squad-c',
          claimedAt: serverTimestamp(),
        });
      }),
    (error) => /PERMISSION_DENIED|permission-denied/i.test(String(error)),
    'the rules must refuse a re-claim inside the stale window'
  );

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.claimedBy, 'squad-b');
});
