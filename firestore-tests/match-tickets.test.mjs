// The `matchTickets` rules, evaluated rather than read.
//
// Everything here was previously verified by a `--dry-run`, which compiles the
// file and proves nothing about a write. This is where the deployed rules
// finally get checked.
//
// **A ticket is spent, never claimed.** This file used to open on the
// ninety-second stale-claim window, the constant mirrored across
// `MatchRules.staleClaim`, `MatchTicket.isClaimable`, the waiting squad's UI
// and the rule. All four are gone: a match is one commit that creates the game
// and spends both tickets, so a ticket is never spoken-for-but-not-spent and
// nothing has to time out. What is left to evaluate is who may spend a ticket,
// and on what — every one of which goes through a whole commit, because a
// half-commit is refused by design.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

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

const GAME_ID = 'game-1';

/** The match a commit creates, matching `SeasonGameService.commitMatch`. */
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

/** Both tickets in the pool, which is where every commit starts. */
function seedBothTickets(overrides = {}) {
  return seed(testEnv, {
    'matchTickets/squad-home': ticketDocument({
      leaderId: 'leader-home',
      memberIds: ['leader-home', 'member-home'],
      courtIds: ['court-1', 'court-2'],
      ...(overrides.home ?? {}),
    }),
    'matchTickets/squad-away': ticketDocument({
      squadId: 'squad-away',
      leaderId: 'leader-away',
      squadName: 'Court Vision',
      memberIds: ['leader-away'],
      courtIds: ['court-1'],
      ...(overrides.away ?? {}),
    }),
  });
}

// MARK: - Spending a ticket

test('a leader may spend both tickets to commit a match', async () => {
  await seedBothTickets();

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertSucceeds(commitMatch(db, gameDocument()));

  const ticket = await readRaw(testEnv, 'matchTickets/squad-home');
  assert.equal(ticket.status, 'matched');
  assert.equal(ticket.claimedBy, 'squad-away');
  assert.equal(ticket.matchedGameId, GAME_ID);
});

test('an expired ticket may not be spent, however open it says it is', async () => {
  await seedBothTickets({ home: { expiresAt: secondsFromNow(-1) } });

  const db = testEnv.authenticatedContext('leader-away').firestore();
  await assertFails(commitMatch(db, gameDocument()));
});

// MARK: - Who may spend

test('a commit on behalf of a squad the caller does not lead is refused', async () => {
  await seedBothTickets();

  // A member of the away squad, not its leader. The rule's single get() against
  // `squads/{claimedBy}` is the whole authorization — this is it failing.
  const db = testEnv.authenticatedContext('member-away').firestore();
  await assertFails(commitMatch(db, gameDocument({ createdBy: 'member-away' })));
});

test('a squad cannot claim itself out of the pool', async () => {
  await seedBothTickets();

  const db = testEnv.authenticatedContext('leader-home').firestore();
  await assertFails(
    commitMatch(db, gameDocument(), { claimedBy: 'squad-home' })
  );
});

test('a commit may not smuggle another field alongside the spend', async () => {
  await seedBothTickets();

  const db = testEnv.authenticatedContext('leader-away').firestore();

  // `memberIds` is the one that matters: it is what the no-shared-players rule
  // reads, so a spend free to rewrite it could match a squad against itself.
  for (const extra of [{ memberIds: ['leader-away'] }, { courtIds: ['court-99'] }]) {
    const batch = writeBatch(db);
    batch.set(doc(db, 'seasonGames', GAME_ID), gameDocument());
    batch.update(doc(db, 'matchTickets', 'squad-home'), {
      status: 'matched',
      claimedBy: 'squad-away',
      claimedAt: serverTimestamp(),
      matchedGameId: GAME_ID,
      ...extra,
    });
    batch.update(doc(db, 'matchTickets', 'squad-away'), {
      status: 'matched',
      matchedGameId: GAME_ID,
    });

    await assertFails(batch.commit());
  }
});

test('a spend cannot be backdated to look fresh forever', async () => {
  await seedBothTickets();

  const db = testEnv.authenticatedContext('leader-away').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'seasonGames', GAME_ID), gameDocument());
  batch.update(doc(db, 'matchTickets', 'squad-home'), {
    status: 'matched',
    claimedBy: 'squad-away',
    claimedAt: secondsFromNow(60 * 60),
    matchedGameId: GAME_ID,
  });
  batch.update(doc(db, 'matchTickets', 'squad-away'), {
    status: 'matched',
    matchedGameId: GAME_ID,
  });

  await assertFails(batch.commit());
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
