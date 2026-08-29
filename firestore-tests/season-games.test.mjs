// The `seasonGames` rules, and the `matched` transition that closes the
// double-booking window.
//
// This is the block where a client names **another squad** in a document it
// writes, so it is the one most worth evaluating rather than reading. The
// authority is a won claim, and the whole question is whether the rule really
// refuses a client that hasn't won one — or that has, but is scheduling the
// match somewhere the home squad never offered.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, deleteDoc, getDoc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

import {
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
 * The fixture every test starts from: two squads, and a home ticket already
 * claimed by the away squad — i.e. the away leader has just won the race and is
 * about to write the game.
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
      status: 'claimed',
      claimedBy: 'squad-away',
      claimedAt: secondsFromNow(-5),
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

/** A well-formed match, matching what `SeasonGameService.createGame` writes. */
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
  await assertSucceeds(setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument()));

  const game = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.deepEqual(game.squadIds, ['squad-home', 'squad-away']);
  assert.equal(game.status, 'scheduled');
});

test('a court absent from the home ticket is rejected; a listed one succeeds', async () => {
  // The prompt's Phase 4 test case #1. The home ticket offers court-1 and
  // court-2; court-9 was never offered by anybody.
  await assertFails(
    setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument({ courtId: 'court-9' }))
  );

  await assertSucceeds(
    setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument({ courtId: 'court-2' }))
  );
});

test('a tip-off outside the home ticket’s window is rejected', async () => {
  // The window is +1h to +5h from now.
  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ scheduledTime: secondsFromNow(60 * 60 * 9) })
    )
  );

  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ scheduledTime: secondsFromNow(60 * 10) })
    )
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
      status: 'claimed',
      claimedBy: 'squad-away',
      claimedAt: secondsFromNow(-5),
    }),
  });

  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ scheduledTime: secondsFromNow(-60 * 10) })
    )
  );
});

test('a squad that never won the claim cannot name the home squad', async () => {
  // The whole authorization, failing. A third squad with a perfectly valid
  // leader and no claim on this ticket.
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
    setDoc(
      doc(thirdDb, 'seasonGames', GAME_ID),
      gameDocument({
        awaySquadId: 'squad-third',
        squadIds: ['squad-home', 'squad-third'],
        awayLeaderId: 'leader-third',
        awaySquadName: 'Baseline',
        createdBy: 'leader-third',
      })
    )
  );
});

test('an unclaimed ticket cannot be turned into a match', async () => {
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      squadId: 'squad-home',
      leaderId: 'leader-home',
      memberIds: ['leader-home', 'member-home'],
      courtIds: ['court-1', 'court-2'],
    }),
  });

  await assertFails(setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument()));
});

test('a forged homeLeaderId is refused — it is what every later write trusts', async () => {
  // If this got through, the away leader would own the home leader's cancel
  // path, and Phase 6's report field with it.
  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ homeLeaderId: 'leader-away' })
    )
  );
});

test('a fabricated squad name is refused', async () => {
  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ homeSquadName: 'Somebody Else' })
    )
  );
});

test('squadIds must be exactly [home, away], in that order', async () => {
  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ squadIds: ['squad-away', 'squad-home'] })
    )
  );

  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ squadIds: ['squad-home', 'squad-away', 'squad-third'] })
    )
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
      setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument(extra)),
      `a create carrying ${Object.keys(extra)[0]} must be refused`
    );
  }

  await assertFails(
    setDoc(
      doc(awayDb(), 'seasonGames', GAME_ID),
      gameDocument({ arrivedPlayerIds: ['leader-away'] })
    )
  );

  await assertFails(
    setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument({ status: 'confirmed' }))
  );
});

test('a match is readable by any signed-in account — season play is public', async () => {
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  const stranger = testEnv.authenticatedContext('nobody').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'seasonGames', GAME_ID)));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'seasonGames', GAME_ID)));
});

// MARK: - Both squads see the same document

test('both squads’ array-contains queries deliver the same match', async () => {
  const { collection, getDocs, query, where } = await import('firebase/firestore');

  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

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
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

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
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

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
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

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
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  for (const uid of ['leader-home', 'leader-away']) {
    const db = testEnv.authenticatedContext(uid).firestore();
    await assertFails(deleteDoc(doc(db, 'seasonGames', GAME_ID)));
  }
});

// MARK: - The `matched` transition

test('the claiming leader may mark the home ticket matched', async () => {
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  await assertSucceeds(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-home'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.status, 'matched');
  assert.equal(ticket.matchedGameId, GAME_ID);
});

test('a leader whose game exists but whose ticket is still claimed marks their OWN ticket matched', async () => {
  // The prompt's Phase 4 test case #2, and the window §2.3 doesn't cover: the
  // away leader died after writing the game and before marking the tickets.
  // The home leader closes it themselves, off their own seasonGames listener,
  // without writing anybody else's document.
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  const homeDb = testEnv.authenticatedContext('leader-home').firestore();
  await assertSucceeds(
    updateDoc(doc(homeDb, 'matchTickets', 'squad-home'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );
});

test('a stranger cannot mark a ticket matched', async () => {
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
  });

  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    updateDoc(doc(thirdDb, 'matchTickets', 'squad-home'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );
});

test('a ticket cannot be marked matched against a game that does not exist', async () => {
  // Otherwise the transition is a way to strand a ticket in a state no listener
  // will ever move it out of.
  await assertFails(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-home'), {
      status: 'matched',
      matchedGameId: 'no-such-game',
    })
  );
});

test('a ticket cannot be marked matched against a game it is not in', async () => {
  await seed(testEnv, {
    'squads/squad-third': squadDocument({
      id: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
    }),
  });

  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  // squad-third's own ticket, pointed at a game between the other two.
  await seed(testEnv, {
    'matchTickets/squad-third': ticketDocument({
      squadId: 'squad-third',
      leaderId: 'leader-third',
      memberIds: ['leader-third'],
      status: 'claimed',
      claimedBy: 'squad-away',
      claimedAt: secondsFromNow(-5),
    }),
  });

  const thirdDb = testEnv.authenticatedContext('leader-third').firestore();
  await assertFails(
    updateDoc(doc(thirdDb, 'matchTickets', 'squad-third'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );
});

test('the matched transition cannot smuggle a re-claim, and a claim cannot smuggle a match', async () => {
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  // One write, one path — the same split `squads` uses.
  await assertFails(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-home'), {
      status: 'matched',
      matchedGameId: GAME_ID,
      claimedBy: 'squad-away',
      claimedAt: serverTimestamp(),
    })
  );
});

test('an open ticket cannot jump straight to matched', async () => {
  await setDoc(doc(awayDb(), 'seasonGames', GAME_ID), gameDocument());

  await seed(testEnv, {
    'matchTickets/squad-away': ticketDocument({
      squadId: 'squad-away',
      leaderId: 'leader-away',
      squadName: 'Court Vision',
      memberIds: ['leader-away', 'member-away'],
    }),
  });

  // squad-away's own ticket is `open`, never claimed. The away leader marks it
  // matched off their own listener — but the transition is claimed → matched,
  // so this is refused and the away ticket is left to expire instead.
  await assertFails(
    updateDoc(doc(awayDb(), 'matchTickets', 'squad-away'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    })
  );
});
