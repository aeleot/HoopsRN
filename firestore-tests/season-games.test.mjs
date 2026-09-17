// The `seasonGames` rules, and the atomic commit that makes a match.
//
// This is the block where a client names **another squad** in a document it
// writes, so it is the one most worth evaluating rather than reading. The
// authority used to be a won claim, seeded here as a `claimed` ticket. It isn't
// any more: a match is one commit that creates the game and spends *both*
// tickets, and the rules make each of the three documents prove the other two.
// So every test here goes through `commitMatch`, and the questions are whether
// the rules refuse a client scheduling the match somewhere the home squad never
// offered — and whether they refuse a commit missing any of its legs.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc,
  deleteDoc,
  getDoc,
  setDoc,
  updateDoc,
  serverTimestamp,
  writeBatch,
} from 'firebase/firestore';

import {
  commitMatch,
  createTestEnvironment,
  readRaw,
  seed,
  secondsFromNow,
  squadDocument,
  ticketDocument,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('season-games');
});

after(async () => {
  await testEnv?.cleanup();
});

const GAME_ID = 'game-1';

/**
 * The fixture every test starts from: two squads, **both tickets open**.
 *
 * It used to seed the home ticket as `claimed`, which is how the two-step
 * design left it between winning a race and writing the game. There is no such
 * state any more — a ticket is in the pool or spent on a match — so the
 * starting point is simply two squads queued, and the commit is what moves
 * them.
 */
beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    'squads/squad-home': squadDocument({
      id: 'squad-home',
      name: 'Rim Reapers',
      nameLower: 'rim reapers',
      leaderId: 'leader-home',
      memberIds: ['leader-home', 'member-home'],
    }),
    'squads/squad-away': squadDocument({
      id: 'squad-away',
      name: 'Court Vision',
      nameLower: 'court vision',
      leaderId: 'leader-away',
      memberIds: ['leader-away', 'member-away'],
    }),
    'matchTickets/squad-home': ticketDocument({
      squadId: 'squad-home',
      leaderId: 'leader-home',
      memberIds: ['leader-home', 'member-home'],
      courtIds: ['court-1', 'court-2'],
    }),
    'matchTickets/squad-away': ticketDocument({
      squadId: 'squad-away',
      leaderId: 'leader-away',
      squadName: 'Court Vision',
      memberIds: ['leader-away', 'member-away'],
      courtIds: ['court-1'],
    }),
  });
});

/** A well-formed match, matching what `SeasonGameService.commitMatch` writes. */
function gameDocument(overrides = {}) {
  return {
    id: GAME_ID,
    format: '3v3',
    region: 'Durham',
    homeSquadId: 'squad-home',
    awaySquadId: 'squad-away',
    squadIds: ['squad-home', 'squad-away'],
    homeLeaderId: 'leader-home',
    awayLeaderId: 'leader-away',
    homeSquadName: 'Rim Reapers',
    awaySquadName: 'Court Vision',
    courtId: 'court-1',
    scheduledTime: secondsFromNow(60 * 90),
    status: 'scheduled',
    arrivedPlayerIds: [],
    createdBy: 'leader-away',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function awayDb() {
  return testEnv.authenticatedContext('leader-away').firestore();
}

// MARK: - Creating a match

test('the leader who won the claim may create the match', async () => {
  await assertSucceeds(commitMatch(awayDb(), gameDocument()));

  const game = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.deepEqual(game.squadIds, ['squad-home', 'squad-away']);
  assert.equal(game.status, 'scheduled');
});

test('a court absent from the home ticket is rejected; a listed one succeeds', async () => {
  // The prompt's Phase 4 test case #1. The home ticket offers court-1 and
  // court-2; court-9 was never offered by anybody.
  await assertFails(
    commitMatch(awayDb(), gameDocument({ courtId: 'court-9' }))
  );

  await assertSucceeds(
    commitMatch(awayDb(), gameDocument({ courtId: 'court-2' }))
  );
});

test('a tip-off outside the home ticket’s window is rejected', async () => {
  // The window is +1h to +5h from now.
  await assertFails(
    commitMatch(awayDb(), gameDocument({ scheduledTime: secondsFromNow(60 * 60 * 9) }))
  );

  await assertFails(
    commitMatch(awayDb(), gameDocument({ scheduledTime: secondsFromNow(60 * 10) }))
  );
});

test('a tip-off in the past is rejected even if the window somehow allows it', async () => {
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      squadId: 'squad-home',
      leaderId: 'leader-home',
      memberIds: ['leader-home', 'member-home'],
      courtIds: ['court-1', 'court-2'],
      windowStart: secondsFromNow(-60 * 60),
      windowEnd: secondsFromNow(60 * 60 * 5),
    }),
  });

  await assertFails(
    commitMatch(awayDb(), gameDocument({ scheduledTime: secondsFromNow(-60 * 10) }))
  );
});

test('a third squad cannot spend two other squads’ tickets', async () => {
  // The whole authorization, failing. A third squad with a perfectly valid
  // leader, committing a match between itself and squad-home — using a ticket
  // that is not its own, since squad-third never queued.
  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      name: 'Baseline',
      nameLower: 'baseline',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
  });

  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    commitMatch(thirdDb, gameDocument({
        awaySquadId: 'squad-third',
        squadIds: ['squad-home', 'squad-third'],
        awayLeaderId: 'leader-third',
        awaySquadName: 'Baseline',
        createdBy: 'leader-third',
      }))
  );
});

// **A commit is all three documents or it is nothing.** Each of these leaves
// one leg out and must be refused — they are the shapes the two-step design
// used to pass through legitimately, one write at a time, and every one of them
// is a way for a squad to end up in two matches or in none.

test('a match cannot be created without spending the home ticket', async () => {
  await assertFails(commitMatch(awayDb(), gameDocument(), { skipHomeTicket: true }));
});

test('a match cannot be created without spending the away ticket', async () => {
  // The leg the old rules never asked for, and the reason two squads could each
  // be in two matches: proving the *home* ticket was claimed said nothing about
  // whether the away squad was still in the pool.
  await assertFails(commitMatch(awayDb(), gameDocument(), { skipAwayTicket: true }));
});

test('tickets cannot be spent without creating the match', async () => {
  await assertFails(commitMatch(awayDb(), gameDocument(), { skipGame: true }));
});

test('a ticket cannot be spent on a different match than the one created', async () => {
  await assertFails(
    commitMatch(awayDb(), gameDocument(), { homeMatchedGameId: 'some-other-game' })
  );
  await assertFails(
    commitMatch(awayDb(), gameDocument(), { awayMatchedGameId: 'some-other-game' })
  );
});

test('the home ticket cannot be credited to a squad that is not the away side', async () => {
  await assertFails(commitMatch(awayDb(), gameDocument(), { claimedBy: 'squad-home' }));
});

test('a ticket already spent cannot be spent again — one live match per squad', async () => {
  // The invariant the whole rework exists for. Once a squad's ticket is gone
  // from the pool, no second commit can take it out again, so no second match
  // can name it.
  await assertSucceeds(commitMatch(awayDb(), gameDocument()));

  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      name: 'Baseline',
      nameLower: 'baseline',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
    'matchTickets/squad-third': ticketDocument({
      squadId: 'squad-third',
      leaderId: 'leader-third',
      squadName: 'Baseline',
      memberIds: ['leader-third'],
      courtIds: ['court-1'],
    }),
  });

  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    commitMatch(
      thirdDb,
      gameDocument({
        id: 'game-2',
        awaySquadId: 'squad-third',
        squadIds: ['squad-home', 'squad-third'],
        awayLeaderId: 'leader-third',
        awaySquadName: 'Baseline',
        createdBy: 'leader-third',
      })
    )
  );
});

test('a forged homeLeaderId is refused — it is what every later write trusts', async () => {
  // If this got through, the away leader would own the home leader's cancel
  // path, and Phase 6's report field with it.
  await assertFails(
    commitMatch(awayDb(), gameDocument({ homeLeaderId: 'leader-away' }))
  );
});

test('a fabricated squad name is refused', async () => {
  await assertFails(
    commitMatch(awayDb(), gameDocument({ homeSquadName: 'Somebody Else' }))
  );
});

test('squadIds must be exactly [home, away], in that order', async () => {
  await assertFails(
    commitMatch(awayDb(), gameDocument({ squadIds: ['squad-away', 'squad-home'] }))
  );

  await assertFails(
    commitMatch(awayDb(), gameDocument({ squadIds: ['squad-home', 'squad-away', 'squad-third'] }))
  );
});

test('a match cannot be born already won, arrived, or cancelled', async () => {
  for (const extra of [
    { result: 'squad-away' },
    { homeReport: 'squad-away' },
    { awayReport: 'squad-away' },
    { confirmedAt: serverTimestamp() },
    { cancelledBySquadId: 'squad-away' },
  ]) {
    await assertFails(
      commitMatch(awayDb(), gameDocument(extra)),
      `a create carrying ${Object.keys(extra)[0]} must be refused`
    );
  }

  await assertFails(
    commitMatch(awayDb(), gameDocument({ arrivedPlayerIds: ['leader-away'] }))
  );

  await assertFails(
    commitMatch(awayDb(), gameDocument({ status: 'confirmed' }))
  );
});

test('a match is readable by any signed-in account — season play is public', async () => {
  await commitMatch(awayDb(), gameDocument());

  const stranger = testEnv.authenticatedContext('nobody').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'seasonGames', GAME_ID)));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'seasonGames', GAME_ID)));
});

// MARK: - Both squads see the same document

test('both squads’ array-contains queries deliver the same match', async () => {
  const { collection, getDocs, query, where } = await import('firebase/firestore');

  await commitMatch(awayDb(), gameDocument());

  const rows = [];
  for (const [uid, squadId] of [
    ['leader-home', 'squad-home'],
    ['leader-away', 'squad-away'],
  ]) {
    const db = testEnv.authenticatedContext(uid).firestore();
    const snapshot = await getDocs(
      query(collection(db, 'seasonGames'), where('squadIds', 'array-contains', squadId))
    );
    assert.equal(snapshot.size, 1, `${squadId} should see exactly one match`);
    rows.push(snapshot.docs[0].data());
  }

  assert.equal(rows[0].courtId, rows[1].courtId);
  assert.equal(rows[0].scheduledTime.toMillis(), rows[1].scheduledTime.toMillis());
  assert.equal(rows[0].id, rows[1].id);
});

// MARK: - Cancellation

test('either leader may cancel, as their own squad only', async () => {
  await commitMatch(awayDb(), gameDocument());

  const homeDb = testEnv.authenticatedContext('leader-home').firestore();

  // A leader cannot cancel *as the other squad* — that would make
  // cancelledBySquadId a field either side can point at the other.
  await assertFails(
    updateDoc(doc(homeDb, 'seasonGames', GAME_ID), {
      status: 'cancelled',
      cancelledBySquadId: 'squad-away',
      updatedAt: serverTimestamp(),
    })
  );

  await assertSucceeds(
    updateDoc(doc(homeDb, 'seasonGames', GAME_ID), {
      status: 'cancelled',
      cancelledBySquadId: 'squad-home',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a member who is not a leader cannot cancel', async () => {
  await commitMatch(awayDb(), gameDocument());

  const memberDb = testEnv.authenticatedContext('member-home').firestore();
  await assertFails(
    updateDoc(doc(memberDb, 'seasonGames', GAME_ID), {
      status: 'cancelled',
      cancelledBySquadId: 'squad-home',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a cancelled match cannot be cancelled again or revived', async () => {
  await commitMatch(awayDb(), gameDocument());

  const homeDb = testEnv.authenticatedContext('leader-home').firestore();
  await updateDoc(doc(homeDb, 'seasonGames', GAME_ID), {
    status: 'cancelled',
    cancelledBySquadId: 'squad-home',
    updatedAt: serverTimestamp(),
  });

  await assertFails(
    updateDoc(doc(homeDb, 'seasonGames', GAME_ID), {
      status: 'scheduled',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a match can never be deleted — a deletable match is a forgeable record', async () => {
  await commitMatch(awayDb(), gameDocument());

  for (const uid of ['leader-home', 'leader-away']) {
    const db = testEnv.authenticatedContext(uid).firestore();
    await assertFails(deleteDoc(doc(db, 'seasonGames', GAME_ID)));
  }
});

// MARK: - Spending a ticket, on its own

// The `matched` transition used to be a write of its own, made twice for one
// match: the claiming leader closed the home ticket, and the home leader closed
// it too, off their own `seasonGames` listener, because the claimer might have
// died in between. Both are gone — a ticket is spent in the same commit that
// creates the match, so there is no second write to make and no window to
// close. What is worth evaluating now is that a ticket **cannot** be spent by
// anything else.

test('a ticket cannot be marked matched outside a commit that creates the match', async () => {
  // Every field the real commit writes, minus the match itself. Legal under the
  // old rules; the point of `getAfter()` is that it is not legal now.
  await assertFails(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-home'), {
      status: 'matched',
      claimedBy: 'squad-away',
      claimedAt: serverTimestamp(),
      matchedGameId: GAME_ID,
    })
  );
});

test('a ticket cannot be pointed at an existing match it is not in', async () => {
  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
    'matchTickets/squad-third': ticketDocument({
      squadId: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
  });

  await assertSucceeds(commitMatch(awayDb(), gameDocument()));

  // squad-third's own ticket, pointed at a match between the other two — a way
  // to strand a ticket in a state no listener will ever move it out of.
  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    updateDoc(doc(thirdDb, 'matchTickets', 'squad-third'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );
});

test('a ticket cannot be marked matched against a match that does not exist', async () => {
  await assertFails(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-home'), {
      status: 'matched',
      claimedBy: 'squad-away',
      claimedAt: serverTimestamp(),
      matchedGameId: 'no-such-game',
    })
  );
});

test('a stranger cannot spend somebody else’s ticket', async () => {
  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
    'matchTickets/squad-third': ticketDocument({
      squadId: 'squad-third',
      leaderId: 'leader-third',
      squadName: 'Baseline',
      memberIds: ['leader-third'],
      courtIds: ['court-1'],
    }),
  });

  // squad-third commits a match it is genuinely in — but spends *squad-away's*
  // ticket for the away leg instead of its own.
  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    commitMatch(
      thirdDb,
      gameDocument({
        awaySquadId: 'squad-third',
        squadIds: ['squad-home', 'squad-third'],
        awayLeaderId: 'leader-third',
        awaySquadName: 'Baseline',
        createdBy: 'leader-third',
      }),
      { awaySquadId: 'squad-away' }
    )
  );
});

test('a commit cannot smuggle a pool field alongside the spend', async () => {
  // The affectedKeys allowlist, from the outside. `memberIds` is what the
  // no-shared-players rule reads, so a spend that could rewrite it would be a
  // spend that could arrange to play yourself.
  // One instance, held: `awayDb()` mints a new Firestore each call, and
  // references from different instances can't share a batch.
  const db = awayDb();
  const batch = writeBatch(db);
  batch.set(doc(db, 'seasonGames', GAME_ID), gameDocument());
  batch.update(doc(db, 'matchTickets', 'squad-home'), {
    status: 'matched',
    claimedBy: 'squad-away',
    claimedAt: serverTimestamp(),
    matchedGameId: GAME_ID,
    memberIds: ['leader-away'],
  });
  batch.update(doc(db, 'matchTickets', 'squad-away'), {
    status: 'matched',
    matchedGameId: GAME_ID,
  });

  await assertFails(batch.commit());
});

test('a successful commit leaves both tickets spent and pointing at the same match', async () => {
  await assertSucceeds(commitMatch(awayDb(), gameDocument()));

  const home = await readRaw(testEnv, 'matchTickets/squad-home');
  const away = await readRaw(testEnv, 'matchTickets/squad-away');

  assert.equal(home.status, 'matched');
  assert.equal(home.claimedBy, 'squad-away');
  assert.ok(home.claimedAt != null, 'claimedAt was never stamped');
  assert.equal(away.status, 'matched');

  // **One match, referred to from both sides.** The two squads no longer hold
  // separate tickets that each have to be reconciled with a match of their own.
  assert.equal(home.matchedGameId, GAME_ID);
  assert.equal(away.matchedGameId, GAME_ID);

  // Nothing else moved.
  assert.deepEqual(home.memberIds, ['leader-home', 'member-home']);
  assert.equal(home.leaderId, 'leader-home');
});
