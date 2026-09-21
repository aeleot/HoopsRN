// The `users` rules, evaluated rather than read.
//
// The simplest of the seven collections — one owner per document — and the one
// whose failure mode is quietest. `users` is readable by every signed-in
// account, because player names have to resolve in shared contexts, and
// Firestore has no field-level read ACLs. So the key allowlist is not a tidiness
// measure: it is the only thing standing between "a profile" and "anything a
// modified client feels like publishing to every user of the app".
//
// `email` was exactly that mistake — written at provisioning, read by nothing,
// visible to everyone. The allowlist landed on `update` first and on `create`
// later, which left the field-level contract enforced only after the first
// write. Both halves are asserted below.
//
// The two `allow update` paths are the other thing worth pinning. Profile edits
// and the stats sync carry disjoint allowlists so one write can never be both,
// the same split `games` draws between roster changes and completion.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

import {
  createTestEnvironment,
  profileDocument,
  readRaw,
  secondsFromNow,
  seed,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('users');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    'users/owner': profileDocument({ id: 'owner' }),
  });
});

// MARK: - Read

test('a profile is readable by any signed-in account, and by nobody signed out', async () => {
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'users', 'owner')));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'users', 'owner')));
});

// MARK: - Create

test('a profile is created by its own account, at its own uid', async () => {
  const base = {
    id: 'newcomer',
    userName: 'Newcomer',
    userNameLower: 'newcomer',
    homeCourtId: 'court-1',
    preferredRadius: 10,
    favoriteCourtIds: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  // Provisioning somebody else's profile.
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertFails(setDoc(doc(stranger, 'users', 'newcomer'), base));

  const db = testEnv.authenticatedContext('newcomer').firestore();

  // The `id` field mirrors the document ID, which is the Auth uid.
  await assertFails(
    setDoc(doc(db, 'users', 'newcomer'), { ...base, id: 'somebody-else' })
  );

  await assertSucceeds(setDoc(doc(db, 'users', 'newcomer'), base));
});

test('a create cannot publish an unlisted field to every signed-in account', async () => {
  // The `email` regression, asserted at the point it originally escaped: the
  // allowlist was on `update` before it was on `create`, so the very first
  // write was the one that got through.
  const db = testEnv.authenticatedContext('newcomer').firestore();

  await assertFails(
    setDoc(doc(db, 'users', 'newcomer'), {
      id: 'newcomer',
      userName: 'Newcomer',
      userNameLower: 'newcomer',
      email: 'newcomer@example.com',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );

  assert.equal(await readRaw(testEnv, 'users/newcomer'), null);
});

test('a display name has to be a non-empty string within the length bound', async () => {
  const db = testEnv.authenticatedContext('newcomer').firestore();
  const base = {
    id: 'newcomer',
    userName: 'Newcomer',
    userNameLower: 'newcomer',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  await assertFails(setDoc(doc(db, 'users', 'newcomer'), { ...base, userName: '' }));
  await assertFails(
    setDoc(doc(db, 'users', 'newcomer'), { ...base, userName: 'x'.repeat(51) })
  );
  await assertSucceeds(
    setDoc(doc(db, 'users', 'newcomer'), { ...base, userName: 'x'.repeat(50) })
  );
});

// MARK: - Profile edits

test('a profile is edited by its owner alone', async () => {
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertFails(
    updateDoc(doc(stranger, 'users', 'owner'), {
      userName: 'Hijacked',
      userNameLower: 'hijacked',
      updatedAt: serverTimestamp(),
    })
  );

  const db = testEnv.authenticatedContext('owner').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'owner'), {
      userName: 'Elliot B',
      userNameLower: 'elliot b',
      updatedAt: serverTimestamp(),
    })
  );

  const profile = await readRaw(testEnv, 'users/owner');
  assert.equal(profile.userName, 'Elliot B');
});

test('id and createdAt are write-once', async () => {
  const db = testEnv.authenticatedContext('owner').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), { id: 'someone-else', updatedAt: serverTimestamp() })
  );

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      createdAt: secondsFromNow(-60 * 60 * 24 * 365),
      updatedAt: serverTimestamp(),
    })
  );
});

test('an edit cannot introduce a field the allowlist does not name', async () => {
  const db = testEnv.authenticatedContext('owner').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      email: 'owner@example.com',
      updatedAt: serverTimestamp(),
    })
  );
});

test('the preferred radius stays inside the range the app offers', async () => {
  const db = testEnv.authenticatedContext('owner').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), { preferredRadius: 0, updatedAt: serverTimestamp() })
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), { preferredRadius: 51, updatedAt: serverTimestamp() })
  );
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'owner'), { preferredRadius: 50, updatedAt: serverTimestamp() })
  );
});

// MARK: - The stats path

test('stats are written by the profile’s owner, as their own path', async () => {
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertFails(
    updateDoc(doc(stranger, 'users', 'owner'), {
      completedGameCount: 99,
      participationStreak: 99,
      updatedAt: serverTimestamp(),
    })
  );

  const db = testEnv.authenticatedContext('owner').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'owner'), {
      completedGameCount: 4,
      participationStreak: 2,
      lastCompletedAt: secondsFromNow(-60 * 60),
      updatedAt: serverTimestamp(),
    })
  );

  const profile = await readRaw(testEnv, 'users/owner');
  assert.equal(profile.completedGameCount, 4);
});

test('a stats sync cannot smuggle in a rename, and a rename cannot forge stats', async () => {
  // Neither allowlist admits the other's keys, which is the entire reason the
  // two paths are separate rather than one permissive rule.
  const db = testEnv.authenticatedContext('owner').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      completedGameCount: 4,
      userName: 'Elliot B',
      updatedAt: serverTimestamp(),
    })
  );

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      userName: 'Elliot B',
      userNameLower: 'elliot b',
      participationStreak: 40,
      updatedAt: serverTimestamp(),
    })
  );
});

test('a negative stat is refused', async () => {
  const db = testEnv.authenticatedContext('owner').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      completedGameCount: -1,
      updatedAt: serverTimestamp(),
    })
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'owner'), {
      participationStreak: -1,
      updatedAt: serverTimestamp(),
    })
  );
});

// MARK: - Delete

test('account deletion is not a supported flow, even for the owner', async () => {
  const db = testEnv.authenticatedContext('owner').firestore();
  await assertFails(deleteDoc(doc(db, 'users', 'owner')));

  assert.notEqual(await readRaw(testEnv, 'users/owner'), null);
});
