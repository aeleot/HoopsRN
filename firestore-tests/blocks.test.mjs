// The `blocks` rules, and the two create rules that consult them.
//
// App Review Guideline 1.2 asks for a way to block abusive users. A block that
// only hid someone in the blocker's own client would be a setting, not a
// block: the blocked person's app — or a modified one — could go on sending
// requests. So the refusal lives in the ruleset. `blocks/{blocker}_{blocked}`
// has a computable ID, and the `friendships` and `squadInvites` create rules
// each spend one exists() on it.
//
// Alice is the blocker throughout, Bob the person she blocked, Carol a
// bystander. 'alice' < 'bob' < 'carol', so the friendship between the first
// two is always `alice_bob`.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  createTestEnvironment,
  friendshipDocument,
  friendshipId,
  inviteDocument,
  readRaw,
  secondsFromNow,
  seed,
  squadDocument,
} from './harness.mjs';

let testEnv;

/** What `SafetyService.block` writes. */
function block(blockerId, blockedId) {
  return { blockerId, blockedId, createdAt: serverTimestamp() };
}

/** A block that already exists, for seeding past the rules. */
function storedBlock(blockerId, blockedId) {
  return { blockerId, blockedId, createdAt: secondsFromNow(-60) };
}

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
  testEnv = await createTestEnvironment('blocks');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// MARK: - Create

test('anyone signed in can block someone else, at the ID derived from the pair', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(setDoc(doc(db, 'blocks', 'alice_bob'), block('alice', 'bob')));
});

test('a block cannot be filed in someone else’s name', async () => {
  const db = testEnv.authenticatedContext('carol').firestore();

  // Carol, making Alice block Bob — which would silently cut Bob off from
  // Alice without either of them having asked for it.
  await assertFails(setDoc(doc(db, 'blocks', 'alice_bob'), block('alice', 'bob')));

  assert.equal(await readRaw(testEnv, 'blocks/alice_bob'), null);
});

test('the document ID is tied to the pair, in blocker-then-blocked order', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  // Reversed. The create rules look a block up at `{blocked's target}_{sender}`,
  // so a block stored the other way round would be one nothing ever finds.
  await assertFails(setDoc(doc(db, 'blocks', 'bob_alice'), block('alice', 'bob')));
  await assertFails(setDoc(doc(db, 'blocks', 'anything'), block('alice', 'bob')));
});

test('you cannot block yourself, and a block carries no extra fields', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertFails(setDoc(doc(db, 'blocks', 'alice_alice'), block('alice', 'alice')));

  await assertFails(
    setDoc(doc(db, 'blocks', 'alice_bob'), { ...block('alice', 'bob'), note: 'rude' })
  );

  // A backdated stamp: `createdAt` is pinned, not requested.
  await assertFails(
    setDoc(doc(db, 'blocks', 'alice_bob'), {
      blockerId: 'alice',
      blockedId: 'bob',
      createdAt: secondsFromNow(-3600),
    })
  );
});

test('a signed-out client cannot block anyone', async () => {
  const db = testEnv.unauthenticatedContext().firestore();

  await assertFails(setDoc(doc(db, 'blocks', 'alice_bob'), block('alice', 'bob')));
});

// MARK: - Read, update, delete

test('only the blocker can see a block — the blocked person cannot', async () => {
  await seed(testEnv, { 'blocks/alice_bob': storedBlock('alice', 'bob') });

  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(getDoc(doc(alice, 'blocks', 'alice_bob')));

  // The listener's shape: every block this account has made.
  const mine = await assertSucceeds(
    getDocs(query(collection(alice, 'blocks'), where('blockerId', '==', 'alice')))
  );
  assert.equal(mine.size, 1);

  // Bob can neither read the document nor ask who has blocked him.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(getDoc(doc(bob, 'blocks', 'alice_bob')));
  await assertFails(
    getDocs(query(collection(bob, 'blocks'), where('blockedId', '==', 'bob')))
  );

  const carol = testEnv.authenticatedContext('carol').firestore();
  await assertFails(getDoc(doc(carol, 'blocks', 'alice_bob')));
});

test('a block is immutable, and only its author can lift it', async () => {
  await seed(testEnv, { 'blocks/alice_bob': storedBlock('alice', 'bob') });

  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertFails(updateDoc(doc(alice, 'blocks', 'alice_bob'), { blockedId: 'carol' }));

  // The person it is aimed at cannot remove it.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(deleteDoc(doc(bob, 'blocks', 'alice_bob')));
  assert.notEqual(await readRaw(testEnv, 'blocks/alice_bob'), null);

  await assertSucceeds(deleteDoc(doc(alice, 'blocks', 'alice_bob')));
});

// MARK: - Friend requests

test('a blocked person’s friend request is refused by the server', async () => {
  await seed(testEnv, { 'blocks/alice_bob': storedBlock('alice', 'bob') });

  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(
    setDoc(doc(bob, 'friendships', 'alice_bob'), pendingRequest('alice', 'bob', 'bob'))
  );

  assert.equal(await readRaw(testEnv, 'friendships/alice_bob'), null);
});

test('the refusal holds whichever side of the pair the blocker sorts on', async () => {
  // Carol blocks Bob: here the *sender* is uidA and the blocker uidB, the
  // mirror image of the case above. A rule that only looked at uidA would
  // pass one of the two.
  await seed(testEnv, { 'blocks/carol_bob': storedBlock('carol', 'bob') });

  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertFails(
    setDoc(doc(bob, 'friendships', 'bob_carol'), pendingRequest('bob', 'carol', 'bob'))
  );
});

test('a block is directional and personal: it stops only that sender, to that person', async () => {
  await seed(testEnv, { 'blocks/alice_bob': storedBlock('alice', 'bob') });

  // Bob can still ask someone who hasn't blocked him.
  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertSucceeds(
    setDoc(doc(bob, 'friendships', 'bob_carol'), pendingRequest('bob', 'carol', 'bob'))
  );

  // Carol can still ask Alice.
  const carol = testEnv.authenticatedContext('carol').firestore();
  await assertSucceeds(
    setDoc(doc(carol, 'friendships', 'alice_carol'), pendingRequest('alice', 'carol', 'carol'))
  );

  // And the rules don't stop Alice asking Bob — her own block isn't a block
  // on her. The app hides the button; the server has no reason to refuse.
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(
    setDoc(doc(alice, 'friendships', 'alice_bob'), pendingRequest('alice', 'bob', 'alice'))
  );
});

test('unblocking puts everything back', async () => {
  await seed(testEnv, { 'blocks/alice_bob': storedBlock('alice', 'bob') });

  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(deleteDoc(doc(alice, 'blocks', 'alice_bob')));

  const bob = testEnv.authenticatedContext('bob').firestore();
  await assertSucceeds(
    setDoc(doc(bob, 'friendships', 'alice_bob'), pendingRequest('alice', 'bob', 'bob'))
  );
});

// MARK: - Squad invites

test('a blocked leader’s squad invite is refused, even while the friendship still stands', async () => {
  // The app removes the friendship when it blocks, which would refuse this
  // invite on its own. This is the case where that delete never happened —
  // the block has to hold without it.
  await seed(testEnv, {
    'squads/squad-bob': squadDocument({
      id: 'squad-bob',
      leaderId: 'bob',
      memberIds: ['bob'],
    }),
    [`friendships/${friendshipId('alice', 'bob')}`]: friendshipDocument('alice', 'bob', 'accepted'),
    [`friendships/${friendshipId('bob', 'carol')}`]: friendshipDocument('bob', 'carol', 'accepted'),
    'blocks/alice_bob': storedBlock('alice', 'bob'),
  });

  const bob = testEnv.authenticatedContext('bob').firestore();

  await assertFails(
    setDoc(doc(bob, 'squadInvites', 'squad-bob_alice'), {
      ...inviteDocument('squad-bob', 'alice', 'bob'),
      createdAt: serverTimestamp(),
    })
  );

  // The same leader inviting a friend who hasn't blocked him is untouched.
  await assertSucceeds(
    setDoc(doc(bob, 'squadInvites', 'squad-bob_carol'), {
      ...inviteDocument('squad-bob', 'carol', 'bob'),
      createdAt: serverTimestamp(),
    })
  );
});
