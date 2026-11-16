// The `reports` rules, evaluated rather than read.
//
// App Review Guideline 1.2 asks for a way to report objectionable content.
// There is no backend to receive one, so a report is a document nobody in the
// app can read: created by its author, read in the Firebase console by whoever
// moderates. The whole rule is "create, in your own name, in this shape — and
// nothing else, ever".

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

import { createTestEnvironment, readRaw, secondsFromNow, seed } from './harness.mjs';

let testEnv;

/** What `SafetyService.submit` writes, with `details` left out by default. */
function report(overrides = {}) {
  return {
    reporterId: 'alice',
    targetType: 'player',
    targetId: 'bob',
    reason: 'harassment',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

before(async () => {
  testEnv = await createTestEnvironment('reports');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// MARK: - Create

test('a signed-in player can report a player, with or without details', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(setDoc(doc(db, 'reports', 'report-1'), report()));
  await assertSucceeds(
    setDoc(doc(db, 'reports', 'report-2'), report({ details: 'Kept messaging after I declined.' }))
  );
});

test('a squad can be reported too', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    setDoc(
      doc(db, 'reports', 'report-1'),
      report({ targetType: 'squad', targetId: 'squad-away', reason: 'offensiveName' })
    )
  );
});

test('every reason the app offers is accepted, and nothing else is', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  const reasons = ['offensiveName', 'harassment', 'spam', 'impersonation', 'other'];
  for (const [index, reason] of reasons.entries()) {
    await assertSucceeds(setDoc(doc(db, 'reports', `report-${index}`), report({ reason })));
  }

  await assertFails(setDoc(doc(db, 'reports', 'report-x'), report({ reason: 'annoying' })));
  await assertFails(setDoc(doc(db, 'reports', 'report-y'), report({ targetType: 'court' })));
});

test('nobody can file a report in someone else’s name', async () => {
  const db = testEnv.authenticatedContext('carol').firestore();

  await assertFails(setDoc(doc(db, 'reports', 'report-1'), report({ reporterId: 'alice' })));

  assert.equal(await readRaw(testEnv, 'reports/report-1'), null);
});

test('a signed-out client cannot report', async () => {
  const db = testEnv.unauthenticatedContext().firestore();

  await assertFails(setDoc(doc(db, 'reports', 'report-1'), report()));
});

test('you cannot report yourself', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertFails(setDoc(doc(db, 'reports', 'report-1'), report({ targetId: 'alice' })));
});

test('unknown fields, a missing field and a backdated stamp are all refused', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  // A field outside the allowlist — the thing that stops this collection
  // becoming somewhere to park arbitrary data.
  await assertFails(setDoc(doc(db, 'reports', 'report-1'), report({ severity: 'high' })));

  const { reason, ...withoutReason } = report();
  await assertFails(setDoc(doc(db, 'reports', 'report-2'), withoutReason));

  await assertFails(
    setDoc(doc(db, 'reports', 'report-3'), report({ createdAt: secondsFromNow(-3600) }))
  );

  await assertFails(setDoc(doc(db, 'reports', 'report-4'), report({ targetId: '' })));
});

test('details are bounded: 500 characters, and absent rather than empty', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'reports', 'report-1'), report({ details: 'x'.repeat(500) }))
  );
  await assertFails(
    setDoc(doc(db, 'reports', 'report-2'), report({ details: 'x'.repeat(501) }))
  );
  await assertFails(setDoc(doc(db, 'reports', 'report-3'), report({ details: '' })));
  await assertFails(setDoc(doc(db, 'reports', 'report-4'), report({ details: 42 })));
});

// MARK: - Read, update, delete

test('no client can read a report — not its author, and not its subject', async () => {
  await seed(testEnv, {
    'reports/report-1': report({ createdAt: secondsFromNow(-60) }),
  });

  for (const uid of ['alice', 'bob', 'carol']) {
    const db = testEnv.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(db, 'reports', 'report-1')));
    await assertFails(getDocs(collection(db, 'reports')));
  }
});

test('a report cannot be edited or withdrawn once filed', async () => {
  await seed(testEnv, {
    'reports/report-1': report({ createdAt: secondsFromNow(-60) }),
  });

  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertFails(updateDoc(doc(alice, 'reports', 'report-1'), { reason: 'spam' }));
  await assertFails(deleteDoc(doc(alice, 'reports', 'report-1')));

  // Nor can its subject make it go away.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(deleteDoc(doc(bob, 'reports', 'report-1')));

  assert.notEqual(await readRaw(testEnv, 'reports/report-1'), null);
});
