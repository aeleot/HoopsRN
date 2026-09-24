// The `friendships` rules, evaluated rather than read.
//
// Walked through by hand with two accounts once, in August, and never since.
// The Friends design listed six manual two-account checks as still
// outstanding; these are those checks, minus the two that are really about the
// client (`FriendService.sendRequest`'s collision recovery) rather than the
// ruleset.
//
// The shape is `games`' membership diff with a smaller state space: two people
// share one document, and the authority is asymmetric and spent in one move.
// The requester spends theirs by creating the edge; the only thing the other
// participant may ever do is accept. Everything else — declining, cancelling,
// unfriending — is the same delete, which is why there is no `declined` status.
//
// Ordering matters throughout: 'alice' < 'bob' < 'carol' lexicographically, so
// the pair document is always `alice_bob`, never `bob_alice`.

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
  friendshipDocument,
  friendshipId,
  readRaw,
  secondsFromNow,
  seed,
} from './harness.mjs';

let testEnv;

/** What a client actually sends to open a request, with both stamps pinned. */
function pendingRequest(uidA, uidB, requestedBy) {
  return {
    uidA,
    uidB,
    requestedBy,
    status: 'pending',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

before(async () => {
  testEnv = await createTestEnvironment('friendships');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    [`friendships/${friendshipId('alice', 'bob')}`]: friendshipDocument(
      'alice',
      'bob',
      'pending'
    ),
  });
});

// MARK: - Read

test('only the two participants know the edge exists', async () => {
  for (const uid of ['alice', 'bob']) {
    const db = testEnv.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(db, 'friendships', 'alice_bob')));
  }

  // Including while it is still pending — an unanswered request is nobody
  // else's business, which is what separates this from `users` and `games`.
  const carol = testEnv.authenticatedContext('carol').firestore();
  await assertFails(getDoc(doc(carol, 'friendships', 'alice_bob')));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'friendships', 'alice_bob')));
});

// MARK: - Create

test('a request is opened by its requester, as one of its own two participants', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'friendships', 'alice_carol'), pendingRequest('alice', 'carol', 'alice'))
  );
});

test('nobody can open a request on someone else’s behalf', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  // Alice, claiming Bob asked.
  await assertFails(
    setDoc(doc(db, 'friendships', 'alice_carol'), pendingRequest('alice', 'carol', 'carol'))
  );

  // Alice, inserting herself into a pair she is not part of.
  await assertFails(
    setDoc(doc(db, 'friendships', 'bob_carol'), pendingRequest('bob', 'carol', 'alice'))
  );

  assert.equal(await readRaw(testEnv, 'friendships/bob_carol'), null);
});

test('the pair is always stored in lexicographic order, at an ID that matches it', async () => {
  const db = testEnv.authenticatedContext('bob').firestore();

  // Reversed: without the ordering check, Bob could open `bob_alice` while
  // Alice independently opened `alice_bob`, and the two copies of one
  // friendship would drift apart.
  await assertFails(
    setDoc(doc(db, 'friendships', 'bob_alice'), pendingRequest('bob', 'alice', 'bob'))
  );

  // Right content, wrong document ID.
  await assertFails(
    setDoc(doc(db, 'friendships', 'something-else'), pendingRequest('bob', 'carol', 'bob'))
  );

  // A pair of one.
  await assertFails(
    setDoc(doc(db, 'friendships', 'bob_bob'), pendingRequest('bob', 'bob', 'bob'))
  );
});

test('a request cannot be born accepted, backdated, or carrying extra keys', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  const base = pendingRequest('alice', 'carol', 'alice');

  // Skipping straight past the other person's consent.
  await assertFails(
    setDoc(doc(db, 'friendships', 'alice_carol'), { ...base, status: 'accepted' })
  );

  await assertFails(
    setDoc(doc(db, 'friendships', 'alice_carol'), {
      ...base,
      createdAt: secondsFromNow(-60 * 60 * 24),
    })
  );

  await assertFails(
    setDoc(doc(db, 'friendships', 'alice_carol'), { ...base, note: 'met at the park' })
  );

  await assertSucceeds(setDoc(doc(db, 'friendships', 'alice_carol'), base));
});

// MARK: - Accept

test('only the recipient may accept, and the requester never can', async () => {
  // The requester already spent their one move by creating the document.
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertFails(
    updateDoc(doc(alice, 'friendships', 'alice_bob'), {
      status: 'accepted',
      updatedAt: serverTimestamp(),
    })
  );

  const carol = testEnv.authenticatedContext('carol').firestore();
  await assertFails(
    updateDoc(doc(carol, 'friendships', 'alice_bob'), {
      status: 'accepted',
      updatedAt: serverTimestamp(),
    })
  );

  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertSucceeds(
    updateDoc(doc(bob, 'friendships', 'alice_bob'), {
      status: 'accepted',
      updatedAt: serverTimestamp(),
    })
  );

  const edge = await readRaw(testEnv, 'friendships/alice_bob');
  assert.equal(edge.status, 'accepted');
});

test('an accepted friendship cannot be walked back to pending', async () => {
  await seed(testEnv, {
    'friendships/alice_bob': friendshipDocument('alice', 'bob', 'accepted'),
  });

  // `resource.data.status == 'pending'` is the precondition, so the only legal
  // transition is the one-way one. Unfriending is a delete, not a downgrade.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(
    updateDoc(doc(bob, 'friendships', 'alice_bob'), {
      status: 'pending',
      updatedAt: serverTimestamp(),
    })
  );
});

test('an accept cannot rewrite who the two people are, or who asked', async () => {
  const bob = testEnv.authenticatedContext('bob').firestore();

  for (const smuggled of [
    { uidA: 'bob' },
    { uidB: 'carol' },
    { requestedBy: 'bob' },
    { note: 'hello' },
  ]) {
    await assertFails(
      updateDoc(doc(bob, 'friendships', 'alice_bob'), {
        status: 'accepted',
        updatedAt: serverTimestamp(),
        ...smuggled,
      })
    );
  }
});

test('the simultaneous-request collision resolves to a refusal, not a second edge', async () => {
  // Both people tap Add before either sees the other's request. The pair has
  // exactly one legal document ID, so Bob's `create`-shaped write lands on
  // Alice's existing document and falls through to the tighter `update`
  // allowlist — where `requestedBy` may not change. `FriendService.sendRequest`
  // catches that refusal and accepts instead, which is the correct signal
  // rather than a bug.
  const bob = testEnv.authenticatedContext('bob').firestore();

  await assertFails(
    setDoc(doc(bob, 'friendships', 'alice_bob'), pendingRequest('alice', 'bob', 'bob'))
  );

  const edge = await readRaw(testEnv, 'friendships/alice_bob');
  assert.equal(edge.requestedBy, 'alice');
  assert.equal(edge.status, 'pending');
});

// MARK: - Delete

test('either participant may remove the edge; a third party may not', async () => {
  const carol = testEnv.authenticatedContext('carol').firestore();
  await assertFails(deleteDoc(doc(carol, 'friendships', 'alice_bob')));

  // Declining, as the recipient.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertSucceeds(deleteDoc(doc(bob, 'friendships', 'alice_bob')));

  // Cancelling, as the requester — the same operation, and the reason
  // re-requesting after a decline works for free: the ID is free again.
  await seed(testEnv, {
    'friendships/alice_bob': friendshipDocument('alice', 'bob', 'pending'),
  });
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(deleteDoc(doc(alice, 'friendships', 'alice_bob')));

  await assertSucceeds(
    setDoc(doc(alice, 'friendships', 'alice_bob'), pendingRequest('alice', 'bob', 'alice'))
  );
});
