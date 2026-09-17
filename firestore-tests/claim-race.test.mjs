// **The match race** — the one guarantee the entire matchmaker rests on.
//
// `context/plans/SEASONS.md` §2.2: there is no server, so matchmaking is pull
// with a lock. Every queued client watches the same pool and the winner of a
// contested transaction gets to make the match. That inversion only works if
// Firestore really does serialize contested transactions such that **exactly
// one** of them wins — and until this file existed, that was a sentence in a
// design document.
//
// It also rests on racing the *right* documents, which is what this file exists
// to pin. The original design claimed a single ticket, and leaned on Firestore
// serializing contested writes to a single document. That is true, and it was
// the wrong guarantee: two squads that pick each other claim two **different**
// tickets, so nothing serializes them, both win, and both go on to create a
// match. In a pool of two squads that is not an edge case — it is the ordinary
// path, and it is what put two live matches in front of both squads.
//
// The commit now reads and writes both tickets and the game together, so the
// two mutual attempts share a read set and Firestore's optimistic concurrency
// finally has something to contend over. `testMutualCommits` below is the
// reported bug, run as a race.
//
// A race that has never been raced is a claim, not a result. So these run
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

/** How many times each race is run. Enough that a lucky pass is unlikely. */
const ROUNDS = 15;

/** Squad names, so the create rule's pin against `squads` can be satisfied. */
const NAMES = {
  'squad-home': 'Rim Reapers',
  'squad-b': 'Court Vision',
  'squad-c': 'Baseline',
};

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
 * `SeasonGameService.commitMatch` in JavaScript, condition for condition.
 *
 * **Both tickets are read, and that is the whole point.** The scan that produced
 * the candidate ran against a pool snapshot that may be seconds stale, and a
 * transaction's own reads are the only view guaranteed current at the moment of
 * the write — but more than that, reading our *own* ticket is what puts it in
 * the read set. Two squads committing against each other then touch the same
 * two documents, so one is retried onto a ticket that is already spent and
 * fails the guard below. Drop the second read and both commit.
 */
function commit(db, { mine, theirs, gameId }) {
  const homeReference = doc(db, 'matchTickets', theirs);
  const awayReference = doc(db, 'matchTickets', mine);
  const gameReference = doc(db, 'seasonGames', gameId);

  return runTransaction(db, async (transaction) => {
    // Every read before every write — Firestore requires it, and this is also
    // what makes the two mutual commits contend.
    const homeSnapshot = await transaction.get(homeReference);
    const awaySnapshot = await transaction.get(awayReference);

    if (!homeSnapshot.exists() || !awaySnapshot.exists()) throw new Error('ticketNotFound');

    const home = homeSnapshot.data();
    const away = awaySnapshot.data();
    const now = Date.now();

    if (home.expiresAt.toMillis() <= now) throw new Error('claimLost');
    if (home.status !== 'open') throw new Error('claimLost');
    // The guard a loser of a mutual race fails on its retry.
    if (away.status !== 'open') throw new Error('claimLost');

    transaction.set(gameReference, {
      id: gameId,
      format: '3v3',
      region: 'Durham',
      homeSquadId: theirs,
      awaySquadId: mine,
      squadIds: [theirs, mine],
      homeLeaderId: home.leaderId,
      awayLeaderId: away.leaderId,
      homeSquadName: NAMES[theirs],
      awaySquadName: NAMES[mine],
      courtId: 'court-1',
      scheduledTime: secondsFromNow(60 * 90),
      status: 'scheduled',
      arrivedPlayerIds: [],
      createdBy: away.leaderId,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    transaction.update(homeReference, {
      status: 'matched',
      claimedBy: mine,
      claimedAt: serverTimestamp(),
      matchedGameId: gameId,
    });

    transaction.update(awayReference, {
      status: 'matched',
      matchedGameId: gameId,
    });
  });
}

function ticketFor(squadId) {
  return ticketDocument({
    squadId,
    leaderId: `leader-${squadId.replace('squad-', '')}`,
    squadName: NAMES[squadId],
    memberIds: [`leader-${squadId.replace('squad-', '')}`],
    courtIds: ['court-1', 'court-2'],
  });
}

function squadFor(squadId) {
  const leader = `leader-${squadId.replace('squad-', '')}`;
  return squadDocument({
    id: squadId,
    name: NAMES[squadId],
    nameLower: NAMES[squadId].toLowerCase(),
    leaderId: leader,
    memberIds: [leader],
  });
}

/** Three squads, each with a ticket in the pool. */
async function seedPool() {
  const docs = {};
  for (const squadId of Object.keys(NAMES)) {
    docs[`squads/${squadId}`] = squadFor(squadId);
    docs[`matchTickets/${squadId}`] = ticketFor(squadId);
  }
  await seed(testEnv, docs);
}

function describe(results) {
  return results
    .filter((result) => result.status === 'rejected')
    .map((result) => result.reason?.message ?? String(result.reason))
    .join(' | ');
}

// MARK: - Two squads, one ticket

test('two concurrent commits on one ticket produce exactly one match', async () => {
  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  const dbC = testEnv.authenticatedContext('leader-c').firestore();

  for (let round = 1; round <= ROUNDS; round += 1) {
    await testEnv.clearFirestore();
    await seedPool();

    const results = await Promise.allSettled([
      commit(dbB, { mine: 'squad-b', theirs: 'squad-home', gameId: 'game-b' }),
      commit(dbC, { mine: 'squad-c', theirs: 'squad-home', gameId: 'game-c' }),
    ]);

    const winners = results.filter((result) => result.status === 'fulfilled');
    assert.equal(
      winners.length,
      1,
      `round ${round}: expected exactly one winner, got ${winners.length}. ${describe(results)}`
    );

    // The loser gets a transaction failure, not a half-written document.
    const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
    assert.equal(ticket.status, 'matched', `round ${round}: ticket status`);
    assert.ok(
      ticket.claimedBy === 'squad-b' || ticket.claimedBy === 'squad-c',
      `round ${round}: claimedBy was ${ticket.claimedBy}`
    );
    assert.ok(ticket.claimedAt != null, `round ${round}: claimedAt was never stamped`);

    // Exactly one match exists, and it is the winner's.
    const gameB = await readRaw(testEnv, 'seasonGames/game-b');
    const gameC = await readRaw(testEnv, 'seasonGames/game-c');
    const games = [gameB, gameC].filter(Boolean);
    assert.equal(games.length, 1, `round ${round}: expected one match, got ${games.length}`);
    assert.equal(games[0].awaySquadId, ticket.claimedBy, `round ${round}: match disagrees with ticket`);

    // Nothing else moved. The spend's affectedKeys allowlist is four fields
    // wide, and a spend that also rewrote the pool fields would be one that
    // could rewrite `memberIds` — the field the no-shared-players rule reads.
    assert.deepEqual(ticket.memberIds, ['leader-home'], `round ${round}: memberIds moved`);
    assert.equal(ticket.squadName, 'Rim Reapers', `round ${round}: squadName moved`);
    assert.equal(ticket.leaderId, 'leader-home', `round ${round}: leaderId moved`);
  }
});

// MARK: - Two squads, each other — the reported bug

test('two squads committing against each other produce exactly one match', async () => {
  // **The duplicate-match bug, run as a race.** Under the two-step design both
  // of these won: they claimed different documents, so nothing serialized them,
  // and each went on to write its own match. Both squads then saw two matches
  // and were told to cancel the one they didn't want — with only one ever
  // having been intended.
  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  const dbC = testEnv.authenticatedContext('leader-c').firestore();

  for (let round = 1; round <= ROUNDS; round += 1) {
    await testEnv.clearFirestore();
    await seedPool();

    const results = await Promise.allSettled([
      commit(dbB, { mine: 'squad-b', theirs: 'squad-c', gameId: 'game-b' }),
      commit(dbC, { mine: 'squad-c', theirs: 'squad-b', gameId: 'game-c' }),
    ]);

    const winners = results.filter((result) => result.status === 'fulfilled');
    assert.equal(
      winners.length,
      1,
      `round ${round}: mutual commits both landed — got ${winners.length} winners. ${describe(results)}`
    );

    const gameB = await readRaw(testEnv, 'seasonGames/game-b');
    const gameC = await readRaw(testEnv, 'seasonGames/game-c');
    const games = [gameB, gameC].filter(Boolean);
    assert.equal(
      games.length,
      1,
      `round ${round}: expected one match between the pair, got ${games.length}`
    );

    // **One match, referred to from both sides.** Both tickets are spent, and
    // both name the same match — which is what the squads' own screens read.
    const ticketB = await readRaw(testEnv, 'matchTickets/squad-b');
    const ticketC = await readRaw(testEnv, 'matchTickets/squad-c');
    assert.equal(ticketB.status, 'matched', `round ${round}: squad-b ticket`);
    assert.equal(ticketC.status, 'matched', `round ${round}: squad-c ticket`);
    assert.equal(
      ticketB.matchedGameId,
      ticketC.matchedGameId,
      `round ${round}: the two squads point at different matches`
    );
    assert.equal(ticketB.matchedGameId, games[0].id, `round ${round}: tickets disagree with the match`);
  }
});

// MARK: - Arriving after the race

test('a commit against an already-spent ticket fails the in-transaction guard', async () => {
  await seedPool();

  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  const dbC = testEnv.authenticatedContext('leader-c').firestore();

  await commit(dbB, { mine: 'squad-b', theirs: 'squad-home', gameId: 'game-b' });

  // Sequential, not concurrent: this is the *second* squad arriving after the
  // match has already been made, which is the common case in a live pool — the
  // pool snapshot is a second old and the ticket has moved on.
  await assert.rejects(
    () => commit(dbC, { mine: 'squad-c', theirs: 'squad-home', gameId: 'game-c' }),
    /claimLost/,
    'a commit against a spent ticket must fail the in-transaction guard'
  );

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.claimedBy, 'squad-b');
  assert.equal(await readRaw(testEnv, 'seasonGames/game-c'), null);
});

test('a squad whose own ticket is spent cannot commit again, even if it skips its own guard', async () => {
  // The Swift guard is a courtesy to the pool, not the enforcement. A modified
  // client that dropped it must still be refused server-side, or "one live
  // match per squad" would be advisory.
  await seedPool();

  const dbB = testEnv.authenticatedContext('leader-b').firestore();
  await commit(dbB, { mine: 'squad-b', theirs: 'squad-home', gameId: 'game-b' });

  const homeReference = doc(dbB, 'matchTickets', 'squad-c');
  const awayReference = doc(dbB, 'matchTickets', 'squad-b');
  const gameReference = doc(dbB, 'seasonGames', 'game-b2');

  await assert.rejects(
    () =>
      runTransaction(dbB, async (transaction) => {
        await transaction.get(homeReference);
        await transaction.get(awayReference);

        transaction.set(gameReference, {
          id: 'game-b2',
          format: '3v3',
          region: 'Durham',
          homeSquadId: 'squad-c',
          awaySquadId: 'squad-b',
          squadIds: ['squad-c', 'squad-b'],
          homeLeaderId: 'leader-c',
          awayLeaderId: 'leader-b',
          homeSquadName: NAMES['squad-c'],
          awaySquadName: NAMES['squad-b'],
          courtId: 'court-1',
          scheduledTime: secondsFromNow(60 * 90),
          status: 'scheduled',
          arrivedPlayerIds: [],
          createdBy: 'leader-b',
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
        transaction.update(homeReference, {
          status: 'matched',
          claimedBy: 'squad-b',
          claimedAt: serverTimestamp(),
          matchedGameId: 'game-b2',
        });
        transaction.update(awayReference, {
          status: 'matched',
          matchedGameId: 'game-b2',
        });
      }),
    (error) => /PERMISSION_DENIED|permission-denied/i.test(String(error)),
    'the rules must refuse a second match for a squad whose ticket is already spent'
  );

  assert.equal(await readRaw(testEnv, 'seasonGames/game-b2'), null);
});
