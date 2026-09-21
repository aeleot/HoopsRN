// The `games` rules, evaluated rather than read.
//
// `games` is the oldest shared, multi-user state in the app and the only one of
// the original three collections that had never been checked by hand at all —
// `friendships` was walked through once in August, `games` never. Everything
// here was previously guaranteed by reading the ruleset and believing it.
//
// The load-bearing rule is the membership diff: two different people write one
// document, and each may only ever move themselves across the two rosters. It
// is the pattern `squads` and `friendships` were both derived from, so a hole
// here is a hole in the shape three collections share.
//
// The duplicate-roster check is the subtle half of that. A set difference is
// only a faithful proxy for a stored list when the list has no duplicates:
// ['host','me','me','me'] reads as a single addition to a set comparison, so
// without the no-duplicates guard one player consumes every seat and locks the
// run to `full`. `squads.test.mjs` asserts its own copy; this is the original.

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
  gameDocument,
  readRaw,
  secondsFromNow,
  seed,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('games');
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(testEnv, {
    'games/game-public': gameDocument({
      id: 'game-public',
      hostId: 'host',
      playerIds: ['host', 'regular'],
      maxPlayers: 10,
    }),
    'games/game-private': gameDocument({
      id: 'game-private',
      hostId: 'host',
      isPublic: false,
      playerIds: ['host'],
      queuedPlayerIds: ['waiting'],
      maxPlayers: 10,
    }),
  });
});

// MARK: - Read

test('a public run is readable by any signed-in account, and by nobody signed out', async () => {
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertSucceeds(getDoc(doc(stranger, 'games', 'game-public')));

  const signedOut = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(signedOut, 'games', 'game-public')));
});

test('a private run is readable only by the people on it', async () => {
  // The roster *and* the waitlist — someone holding a queue place has to be
  // able to see the run they are queued for.
  for (const uid of ['host', 'waiting']) {
    const db = testEnv.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(db, 'games', 'game-private')));
  }

  // This is the whole of the privacy model for an invite-only run: no rule
  // consults `friendships`, so a friend who isn't on the roster is a stranger
  // here. `plans/FRIENDS.md` §4 defers that deliberately.
  const stranger = testEnv.authenticatedContext('stranger').firestore();
  await assertFails(getDoc(doc(stranger, 'games', 'game-private')));
});

// MARK: - Create

test('a run is created by its host, alone, inside every bound', async () => {
  const db = testEnv.authenticatedContext('founder').firestore();

  const base = {
    id: 'game-new',
    hostId: 'founder',
    courtId: 'court-9',
    scheduledTime: secondsFromNow(60 * 60),
    isPublic: true,
    maxPlayers: 10,
    status: 'open',
    playerIds: ['founder'],
    queuedPlayerIds: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  // Hosting on someone else's behalf.
  await assertFails(setDoc(doc(db, 'games', 'game-new'), { ...base, hostId: 'someone' }));

  // Seeding a roster at creation means writing other people's uids.
  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), { ...base, playerIds: ['founder', 'friend'] })
  );
  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), { ...base, queuedPlayerIds: ['friend'] })
  );

  // The `id` field mirrors the document ID so the client decodes without a
  // `@DocumentID` wrapper; nothing keeps them honest but this.
  await assertFails(setDoc(doc(db, 'games', 'game-elsewhere'), base));

  // Bounded on both sides: no runs in the past, none parked a year out.
  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), { ...base, scheduledTime: secondsFromNow(-60) })
  );
  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), {
      ...base,
      scheduledTime: secondsFromNow(31 * 24 * 60 * 60),
    })
  );

  await assertFails(setDoc(doc(db, 'games', 'game-new'), { ...base, maxPlayers: 1 }));
  await assertFails(setDoc(doc(db, 'games', 'game-new'), { ...base, maxPlayers: 31 }));
  await assertFails(setDoc(doc(db, 'games', 'game-new'), { ...base, courtId: '' }));

  // `status` is derived, never chosen — one player is not a full run.
  await assertFails(setDoc(doc(db, 'games', 'game-new'), { ...base, status: 'full' }));

  // An unlisted key on a document every signed-in account can read.
  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), { ...base, note: 'bring water' })
  );

  await assertSucceeds(setDoc(doc(db, 'games', 'game-new'), base));
});

test('a create cannot backdate itself to look older than it is', async () => {
  // `createdAt`/`updatedAt` are pinned to `request.time`, which is what makes a
  // server timestamp enforced rather than merely requested.
  const db = testEnv.authenticatedContext('founder').firestore();

  await assertFails(
    setDoc(doc(db, 'games', 'game-new'), {
      id: 'game-new',
      hostId: 'founder',
      courtId: 'court-9',
      scheduledTime: secondsFromNow(60 * 60),
      isPublic: true,
      maxPlayers: 10,
      status: 'open',
      playerIds: ['founder'],
      queuedPlayerIds: [],
      createdAt: secondsFromNow(-60 * 60 * 24),
      updatedAt: serverTimestamp(),
    })
  );
});

// MARK: - The membership diff

test('joining adds only the caller', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertSucceeds(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  const game = await readRaw(testEnv, 'games/game-public');
  assert.deepEqual(game.playerIds, ['host', 'regular', 'joiner']);
});

test('a roster write that moves anyone but the caller is refused', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  // Adding a third party alongside yourself.
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner', 'stranger'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  // Joining while dropping someone else. This is also why a freed slot is never
  // handed to the first waitlisted player: promoting somebody means writing
  // their uid, and that is this exact refusal.
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'joiner'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  // Removing someone else while touching nothing of your own.
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  const game = await readRaw(testEnv, 'games/game-public');
  assert.deepEqual(game.playerIds, ['host', 'regular']);
});

test('a duplicated roster entry is refused — the hole the set diff would miss', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner', 'joiner', 'joiner', 'joiner'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  // And on the waitlist, which has its own copy of the check.
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular'],
      queuedPlayerIds: ['joiner', 'joiner'],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  const game = await readRaw(testEnv, 'games/game-public');
  assert.deepEqual(game.playerIds, ['host', 'regular']);
});

test('the rosters stay disjoint — nobody is confirmed and waitlisted at once', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner'],
      queuedPlayerIds: ['joiner'],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );
});

test('the host cannot leave their own run; a player can', async () => {
  const hostDb = testEnv.authenticatedContext('host').firestore();
  await assertFails(
    updateDoc(doc(hostDb, 'games', 'game-public'), {
      playerIds: ['regular'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );

  const playerDb = testEnv.authenticatedContext('regular').firestore();
  await assertSucceeds(
    updateDoc(doc(playerDb, 'games', 'game-public'), {
      playerIds: ['host'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a run cannot be overfilled, but its waitlist is unbounded', async () => {
  await seed(testEnv, {
    'games/game-full': gameDocument({
      id: 'game-full',
      hostId: 'host',
      playerIds: ['host', 'second'],
      maxPlayers: 2,
    }),
  });

  const db = testEnv.authenticatedContext('joiner').firestore();

  await assertFails(
    updateDoc(doc(db, 'games', 'game-full'), {
      playerIds: ['host', 'second', 'joiner'],
      queuedPlayerIds: [],
      status: 'full',
      updatedAt: serverTimestamp(),
    })
  );

  // The waitlist is where a full run puts you, and it has no ceiling — that is
  // `GameService.mutateRoster`'s fallback, and the rules have to admit it.
  await assertSucceeds(
    updateDoc(doc(db, 'games', 'game-full'), {
      playerIds: ['host', 'second'],
      queuedPlayerIds: ['joiner'],
      status: 'full',
      updatedAt: serverTimestamp(),
    })
  );
});

test('status has to keep agreeing with the roster it ships alongside', async () => {
  const db = testEnv.authenticatedContext('joiner').firestore();

  // Joining a run with room while claiming it is now full.
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner'],
      queuedPlayerIds: [],
      status: 'full',
      updatedAt: serverTimestamp(),
    })
  );
});

test('a roster write cannot edit the run itself', async () => {
  // There is no "edit a run" path at all: court, time, visibility, size and
  // host are immutable once created, so the only thing to secure is that a
  // join cannot smuggle one of them through.
  const db = testEnv.authenticatedContext('joiner').firestore();

  const join = {
    playerIds: ['host', 'regular', 'joiner'],
    queuedPlayerIds: [],
    status: 'open',
    updatedAt: serverTimestamp(),
  };

  for (const smuggled of [
    { courtId: 'court-elsewhere' },
    { scheduledTime: secondsFromNow(60 * 60 * 5) },
    { isPublic: false },
    { maxPlayers: 30 },
    { hostId: 'joiner' },
  ]) {
    await assertFails(
      updateDoc(doc(db, 'games', 'game-public'), { ...join, ...smuggled })
    );
  }
});

// MARK: - Completion

test('completion is the host’s alone, and one-way', async () => {
  const playerDb = testEnv.authenticatedContext('regular').firestore();
  await assertFails(
    updateDoc(doc(playerDb, 'games', 'game-public'), {
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );

  const hostDb = testEnv.authenticatedContext('host').firestore();
  await assertSucceeds(
    updateDoc(doc(hostDb, 'games', 'game-public'), {
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );

  // `resource.data.status != 'completed'` is what makes the second write a
  // refusal rather than a re-stamp — there is no un-complete path by design,
  // and a re-stamp would let a host walk `completedAt` forward to keep a
  // participation streak alive.
  await assertFails(
    updateDoc(doc(hostDb, 'games', 'game-public'), {
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );
});

test('a completion cannot be backdated to inflate a streak', async () => {
  const db = testEnv.authenticatedContext('host').firestore();

  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      status: 'completed',
      completedAt: secondsFromNow(-60 * 60 * 24 * 7),
      updatedAt: serverTimestamp(),
    })
  );
});

test('completing and changing the roster are separate writes', async () => {
  // The two update paths carry disjoint key allowlists precisely so one write
  // can never be both.
  const db = testEnv.authenticatedContext('host').firestore();

  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      status: 'completed',
      completedAt: serverTimestamp(),
      playerIds: ['host'],
      updatedAt: serverTimestamp(),
    })
  );
});

test('a completed run stops taking players', async () => {
  const hostDb = testEnv.authenticatedContext('host').firestore();
  await assertSucceeds(
    updateDoc(doc(hostDb, 'games', 'game-public'), {
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );

  const db = testEnv.authenticatedContext('joiner').firestore();
  await assertFails(
    updateDoc(doc(db, 'games', 'game-public'), {
      playerIds: ['host', 'regular', 'joiner'],
      queuedPlayerIds: [],
      status: 'open',
      updatedAt: serverTimestamp(),
    })
  );
});

// MARK: - Delete

test('cancelling is the host’s alone', async () => {
  const playerDb = testEnv.authenticatedContext('regular').firestore();
  await assertFails(deleteDoc(doc(playerDb, 'games', 'game-public')));

  const strangerDb = testEnv.authenticatedContext('stranger').firestore();
  await assertFails(deleteDoc(doc(strangerDb, 'games', 'game-public')));

  const hostDb = testEnv.authenticatedContext('host').firestore();
  await assertSucceeds(deleteDoc(doc(hostDb, 'games', 'game-public')));
});
