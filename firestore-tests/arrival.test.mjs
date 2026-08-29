// `arrivedPlayerIds` — the existing self-only membership pattern verbatim, and
// the field the plan calls out as "the moment a squad sees they're first to
// the court." Evaluated the same way the rest of Seasons' contested paths are:
// against the real emulator, not read as text.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

import {
  createTestEnvironment,
  readRaw,
  seed,
  secondsFromNow,
  squadDocument,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('arrival');
});

after(async () => {
  await testEnv?.cleanup();
});

const GAME_ID = 'game-1';

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

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    'squads/squad-home': squadDocument({
      id: 'squad-home',
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
  });

  // Seeded directly rather than via the create rule: this file is about the
  // arrival path, and going through create here would just be re-testing
  // season-games.test.mjs.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'seasonGames', GAME_ID), gameDocument());
  });
});

test('a caller may add their own uid to arrivedPlayerIds', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertSucceeds(
    updateDoc(doc(db, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['leader-home'] })
  );

  const game = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.deepEqual(game.arrivedPlayerIds, ['leader-home']);
});

test('adding a uid other than the caller’s own is rejected', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['member-home'] })
  );

  // Even alongside their own — the diff must be *exactly* the caller's uid.
  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['leader-home', 'member-home'],
    })
  );
});

test('any member of either squad may mark arrival, not leaders only', async () => {
  const homeMemberDb = testEnv.authenticatedContext('member-home').firestore();
  await assertSucceeds(
    updateDoc(doc(homeMemberDb, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['member-home'] })
  );

  const awayMemberDb = testEnv.authenticatedContext('member-away').firestore();
  await assertSucceeds(
    updateDoc(doc(awayMemberDb, 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['member-home', 'member-away'],
    })
  );
});

test('someone on neither squad cannot mark arrival', async () => {
  const strangerDb = testEnv.authenticatedContext('stranger').firestore();

  await assertFails(
    updateDoc(doc(strangerDb, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['stranger'] })
  );
});

test('a duplicate entry is refused — the same hole the set diff would miss elsewhere', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['leader-home', 'leader-home'],
    })
  );
});

test('arrival has no undo — removing an already-arrived uid is refused', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['leader-home'],
    });
  });

  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertFails(updateDoc(doc(db, 'seasonGames', GAME_ID), { arrivedPlayerIds: [] }));
});

test('re-marking arrival for someone already arrived is refused, not merely a no-op', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['leader-home'],
    });
  });

  const db = testEnv.authenticatedContext('leader-home').firestore();

  // The diff would be empty — hasOnly([uid]) on an empty set is vacuously
  // true — so this is refused by the "not already in the array" guard, the
  // same idiom `squads`' self-join uses.
  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['leader-home'] })
  );
});

test('arrival is refused once a match is no longer scheduled', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'seasonGames', GAME_ID), {
      status: 'cancelled',
      cancelledBySquadId: 'squad-home',
    });
  });

  const db = testEnv.authenticatedContext('leader-home').firestore();
  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['leader-home'] })
  );
});

test('an arrival write cannot smuggle another field alongside it', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertFails(
    updateDoc(doc(db, 'seasonGames', GAME_ID), {
      arrivedPlayerIds: ['leader-home'],
      status: 'confirmed',
    })
  );
});

test('both squads read the same arrival array off the same document', async () => {
  const homeDb = testEnv.authenticatedContext('leader-home').firestore();
  await updateDoc(doc(homeDb, 'seasonGames', GAME_ID), { arrivedPlayerIds: ['leader-home'] });

  const awayDb = testEnv.authenticatedContext('leader-away').firestore();
  const snapshot = await getDoc(doc(awayDb, 'seasonGames', GAME_ID));

  assert.deepEqual(snapshot.data().arrivedPlayerIds, ['leader-home']);
});
