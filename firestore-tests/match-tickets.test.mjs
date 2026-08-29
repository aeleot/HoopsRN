// The `matchTickets` rules, evaluated rather than read.
//
// Everything here was previously verified by a `--dry-run`, which compiles the
// file and proves nothing about a write. The stale-claim constant in
// particular is mirrored in four places — `MatchRules.staleClaim`,
// `MatchTicket.isClaimable`, the waiting squad's UI, and the rule below — and
// `FirestoreRulesParityTests` can only compare the first three against the
// *text* of the fourth. This is where the deployed rule finally gets checked.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

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
  testEnv = await createTestEnvironment('match-tickets');
});

after(async () => {
  await testEnv?.cleanup();
});

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
      memberIds: ['leader-away'],
    }),
  });
});

/** The claim write, exactly as `MatchmakingService` issues it. */
function claimWrite(claimingSquadId) {
  return {
    status: 'claimed',
    claimedBy: claimingSquadId,
    claimedAt: serverTimestamp(),
  };
}

// MARK: - The stale-claim window

test('a claim 91 seconds old may be re-claimed', async () => {
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      status: 'claimed',
      claimedBy: 'squad-gone',
      claimedAt: secondsFromNow(-91),
    }),
  });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-away'))
  );

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.claimedBy, 'squad-away');
});

test('a claim 89 seconds old may not be re-claimed', async () => {
  // Seeded immediately before the assertion so the two seconds of margin are
  // real ones. The boundary is 90; this test and the one above are the two
  // sides of it.
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      status: 'claimed',
      claimedBy: 'squad-holding',
      claimedAt: secondsFromNow(-89),
    }),
  });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-away'))
  );
});

test('an open ticket may be claimed', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-away'))
  );
});

test('an expired ticket may not be claimed, however open it says it is', async () => {
  await seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({ expiresAt: secondsFromNow(-1) }),
  });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-away'))
  );
});

// MARK: - Who may claim

test('a claim on behalf of a squad the caller does not lead is refused', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  // A member of the away squad, not its leader. The rule's single get() against
  // `squads/{claimedBy}` is the whole authorization — this is it failing.
  const db = testEnv.authenticatedContext('member-away').firestore();
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-away'))
  );
});

test('a squad cannot claim itself out of the pool', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const db = testEnv.authenticatedContext('leader-home').firestore();
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), claimWrite('squad-home'))
  );
});

test('a claim may not smuggle another field alongside it', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const db = testEnv.authenticatedContext('leader-away').firestore();

  // `memberIds` is the one that matters: it is what the no-shared-players rule
  // reads, so a claim free to rewrite it could match a squad against itself.
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...claimWrite('squad-away'),
      memberIds: ['leader-away'],
    })
  );

  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...claimWrite('squad-away'),
      courtIds: ['court-99'],
    })
  );
});

test('a claim cannot be backdated to look fresh forever', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertFails(
    updateDoc(doc(db, 'matchTickets', 'squad-home'), {
      status: 'claimed',
      claimedBy: 'squad-away',
      claimedAt: secondsFromNow(60 * 60),
    })
  );
});

// MARK: - Queueing

test('a leader may queue their own squad, and the denormalized fields are pinned', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...ticketDocument({ memberIds: ['leader-home', 'member-home'] }),
      createdAt: serverTimestamp(),
    })
  );
});

test('a forged memberIds on a ticket is refused', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  // The one field a client must not be free to write about itself: a ticket
  // claiming an empty roster shares no players with anybody, which is how a
  // squad would match against itself.
  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...ticketDocument({ memberIds: [] }),
      createdAt: serverTimestamp(),
    })
  );
});

test('only a squad leader may queue it', async () => {
  const db = testEnv.authenticatedContext('member-home').firestore();

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...ticketDocument({ leaderId: 'member-home' }),
      createdAt: serverTimestamp(),
    })
  );
});

test('a ticket enters the pool open, never pre-claimed', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...ticketDocument({
        memberIds: ['leader-home', 'member-home'],
        status: 'claimed',
      }),
      createdAt: serverTimestamp(),
    })
  );
});

test('the court selection bounds are enforced server-side', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();
  const base = ticketDocument({ memberIds: ['leader-home', 'member-home'] });

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...base,
      courtIds: [],
      createdAt: serverTimestamp(),
    })
  );

  // A duplicate would skew the intersection the match rules take, and a
  // preference order can't rank a court against itself.
  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...base,
      courtIds: ['court-1', 'court-1'],
      createdAt: serverTimestamp(),
    })
  );

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...base,
      courtIds: Array.from({ length: 9 }, (_, index) => `court-${index}`),
      createdAt: serverTimestamp(),
    })
  );
});

test('the ticket lifetime bounds are enforced server-side', async () => {
  const db = testEnv.authenticatedContext('leader-home').firestore();
  const base = ticketDocument({ memberIds: ['leader-home', 'member-home'] });

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...base,
      expiresAt: secondsFromNow(60 * 14),
      createdAt: serverTimestamp(),
    })
  );

  await assertFails(
    setDoc(doc(db, 'matchTickets', 'squad-home'), {
      ...base,
      expiresAt: secondsFromNow(60 * 60 * 25),
      createdAt: serverTimestamp(),
    })
  );
});

test('leaving the queue is the leader’s alone', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const { deleteDoc } = await import('firebase/firestore');

  const memberDb = testEnv.authenticatedContext('member-home').firestore();
  await assertFails(deleteDoc(doc(memberDb, 'matchTickets', 'squad-home')));

  const leaderDb = testEnv.authenticatedContext('leader-home').firestore();
  await assertSucceeds(deleteDoc(doc(leaderDb, 'matchTickets', 'squad-home')));
});

test('the pool is readable by any signed-in account', async () => {
  await seed(testEnv, { 'matchTickets/squad-home': ticketDocument() });

  const { getDoc } = await import('firebase/firestore');

  const stranger = testEnv.authenticatedContext('somebody-else').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'matchTickets', 'squad-home')));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'matchTickets', 'squad-home')));
});
