// The `squads` and `squadInvites` rules, evaluated rather than read.
//
// Phase 1's third test case — "a self-join write whose `memberIds` diff
// contains a uid other than the caller's is rejected" — shipped as a rules
// dry-run, which is a compile and not an evaluation. It is the first test
// below, finally asserted.
//
// The duplicate-roster check is the second. It is the reason a set difference
// is only a faithful proxy for a stored list when the list has no duplicates,
// it is documented at length in both the `games` and `squads` rules, and
// nothing had ever exercised it.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, deleteDoc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

import {
  createTestEnvironment,
  friendshipDocument,
  friendshipId,
  inviteDocument,
  readRaw,
  seed,
  squadDocument,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('squads');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    'squads/squad-home': squadDocument({
      id: 'squad-home',
      leaderId: 'leader',
      memberIds: ['leader', 'member'],
    }),
    [`squadInvites/squad-home_joiner`]: inviteDocument('squad-home', 'joiner', 'leader'),
  });
});

// MARK: - Self-join

test('a self-join adding only the caller is allowed', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertSucceeds(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'member', 'joiner'],
      updatedAt: serverTimestamp(),
    })
  );

  const squad = await readRaw(testEnv, 'squads/squad-home');
  assert.deepEqual(squad.memberIds, ['leader', 'member', 'joiner']);
});

test('a self-join whose diff contains a uid other than the caller is rejected', async () => {
  // Phase 1 test case #3. A dry-run compiles rules; it cannot evaluate a write.
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'member', 'joiner', 'stranger'],
      updatedAt: serverTimestamp(),
    })
  );

  // …and in the other direction: adding yourself while dropping someone else.
  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'joiner'],
      updatedAt: serverTimestamp(),
    })
  );

  const squad = await readRaw(testEnv, 'squads/squad-home');
  assert.deepEqual(squad.memberIds, ['leader', 'member']);
});

test('a duplicated roster entry is refused — the hole the set diff would miss', async () => {
  // ['leader','me','me','me','me','me'] reads as a *single* addition to a set
  // comparison: six list entries, two set entries. Without the no-duplicates
  // check one member consumes every seat and locks the squad to full.
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'member', 'joiner', 'joiner', 'joiner', 'joiner'],
      updatedAt: serverTimestamp(),
    })
  );

  const squad = await readRaw(testEnv, 'squads/squad-home');
  assert.deepEqual(squad.memberIds, ['leader', 'member']);
});

test('a self-join without an invite is refused', async () => {
  const db = testEnv.authenticatedContext('uninvited').firestore();

  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'member', 'uninvited'],
      updatedAt: serverTimestamp(),
    })
  );
});

test('a self-join past the format roster ceiling is refused', async () => {
  await seed(testEnv, {
    'squads/squad-home': squadDocument({
      id: 'squad-home',
      leaderId: 'leader',
      memberIds: ['leader', 'm1', 'm2', 'm3', 'm4', 'm5'],
    }),
  });

  const db = testEnv.authenticatedContext('joiner').firestore();
  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'm1', 'm2', 'm3', 'm4', 'm5', 'joiner'],
      updatedAt: serverTimestamp(),
    })
  );
});

// MARK: - The three update paths, in isolation

test('a leader edit that also touches memberIds is refused', async () => {
  const db = testEnv.authenticatedContext('leader').firestore();

  await assertSucceeds(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      name: 'Rim Reapers II',
      nameLower: 'rim reapers ii',
      iconKey: 'flame.fill',
      colorKey: 'red',
      updatedAt: serverTimestamp(),
    })
  );

  // The same edit, plus one roster entry. The leader-edit path's allowlist has
  // no `memberIds`; the self-join path's has no `name`. Neither admits this,
  // which is the entire point of splitting them.
  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      name: 'Rim Reapers III',
      nameLower: 'rim reapers iii',
      iconKey: 'flame.fill',
      colorKey: 'red',
      memberIds: ['leader', 'member', 'leader-friend'],
      updatedAt: serverTimestamp(),
    })
  );
});

test('a join that also renames the squad is refused', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'squads', 'squad-home'), {
      memberIds: ['leader', 'member', 'joiner'],
      name: 'Joiner FC',
      nameLower: 'joiner fc',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a leader cannot self-leave; a member can', async () => {
  const leaderDb = testEnv.authenticatedContext('leader').firestore();
  await assertFails(
    updateDoc(doc(leaderDb, 'squads', 'squad-home'), {
      memberIds: ['member'],
      updatedAt: serverTimestamp(),
    })
  );

  const memberDb = testEnv.authenticatedContext('member').firestore();
  await assertSucceeds(
    updateDoc(doc(memberDb, 'squads', 'squad-home'), {
      memberIds: ['leader'],
      updatedAt: serverTimestamp(),
    })
  );
});

test('only the leader may disband', async () => {
  const memberDb = testEnv.authenticatedContext('member').firestore();
  await assertFails(deleteDoc(doc(memberDb, 'squads', 'squad-home')));

  const leaderDb = testEnv.authenticatedContext('leader').firestore();
  await assertSucceeds(deleteDoc(doc(leaderDb, 'squads', 'squad-home')));
});

test('a squad is readable by any signed-in account — an opponent renders your crest', async () => {
  const { getDoc } = await import('firebase/firestore');

  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'squads', 'squad-home')));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'squads', 'squad-home')));
});

test('a squad is created by its leader, alone, with an allowlisted crest', async () => {
  const db = testEnv.authenticatedContext('founder').firestore();

  const base = {
    id: 'squad-new',
    name: 'Baseline',
    nameLower: 'baseline',
    leaderId: 'founder',
    memberIds: ['founder'],
    format: '3v3',
    iconKey: 'bolt.fill',
    colorKey: 'teal',
    region: 'Durham',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  // A roster at creation would mean writing other people's uids.
  await assertFails(
    setDoc(doc(db, 'squads', 'squad-new'), { ...base, memberIds: ['founder', 'friend'] })
  );

  await assertFails(
    setDoc(doc(db, 'squads', 'squad-new'), { ...base, iconKey: 'skull.fill' })
  );

  await assertFails(
    setDoc(doc(db, 'squads', 'squad-new'), { ...base, format: '5v5' })
  );

  await assertFails(setDoc(doc(db, 'squads', 'squad-new'), { ...base, name: 'RR' }));

  await assertSucceeds(setDoc(doc(db, 'squads', 'squad-new'), base));
});

// MARK: - The invite friendship gate

test('an invite to a stranger is refused, to a pending friend refused, to an accepted friend allowed', async () => {
  const db = testEnv.authenticatedContext('leader').firestore();

  // A stranger — no friendship document at all.
  await assertFails(
    setDoc(doc(db, 'squadInvites', 'squad-home_stranger'), {
      ...inviteDocument('squad-home', 'stranger', 'leader'),
      createdAt: serverTimestamp(),
    })
  );

  // A pending request is not yet a friendship. This is the four lines that
  // separate "squads are built from your friends" from "anyone can spam
  // invites at strangers".
  await seed(testEnv, {
    [`friendships/${friendshipId('leader', 'pending-friend')}`]: friendshipDocument(
      'leader',
      'pending-friend',
      'pending'
    ),
  });

  await assertFails(
    setDoc(doc(db, 'squadInvites', 'squad-home_pending-friend'), {
      ...inviteDocument('squad-home', 'pending-friend', 'leader'),
      createdAt: serverTimestamp(),
    })
  );

  await seed(testEnv, {
    [`friendships/${friendshipId('leader', 'real-friend')}`]: friendshipDocument(
      'leader',
      'real-friend',
      'accepted'
    ),
  });

  await assertSucceeds(
    setDoc(doc(db, 'squadInvites', 'squad-home_real-friend'), {
      ...inviteDocument('squad-home', 'real-friend', 'leader'),
      createdAt: serverTimestamp(),
    })
  );
});

test('only a squad’s leader may invite to it, and the document ID is tied to the pair', async () => {
  await seed(testEnv, {
    [`friendships/${friendshipId('member', 'their-friend')}`]: friendshipDocument(
      'member',
      'their-friend',
      'accepted'
    ),
    [`friendships/${friendshipId('leader', 'real-friend')}`]: friendshipDocument(
      'leader',
      'real-friend',
      'accepted'
    ),
  });

  // A member, not the leader.
  const memberDb = testEnv.authenticatedContext('member').firestore();
  await assertFails(
    setDoc(doc(memberDb, 'squadInvites', 'squad-home_their-friend'), {
      ...inviteDocument('squad-home', 'their-friend', 'member'),
      createdAt: serverTimestamp(),
    })
  );

  // The leader, with a document ID that doesn't match its own content.
  const leaderDb = testEnv.authenticatedContext('leader').firestore();
  await assertFails(
    setDoc(doc(leaderDb, 'squadInvites', 'some-other-id'), {
      ...inviteDocument('squad-home', 'real-friend', 'leader'),
      createdAt: serverTimestamp(),
    })
  );
});

test('an invite is immutable — every outcome is a delete', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'squadInvites', 'squad-home_joiner'), {
      squadId: 'squad-elsewhere',
    })
  );

  await assertSucceeds(deleteDoc(doc(db, 'squadInvites', 'squad-home_joiner')));
});
