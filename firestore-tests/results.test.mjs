// Reporting, mutual confirmation, and the disputed state.
//
// **This is the file the reporting design exists to be checked by.** Mutual
// confirmation's entire subject is *two different people agreeing or
// disagreeing with each other*, which no single-client test can exercise and no
// dry-run can evaluate. Every test below uses two distinct authenticated
// contexts for exactly that reason: one context calling twice would prove
// nothing about the rule that pins each report field to its own leader.

import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteField, serverTimestamp } from 'firebase/firestore';

import {
  createTestEnvironment,
  readRaw,
  seed,
  secondsFromNow,
  squadDocument,
} from './harness.mjs';

let testEnv;

before(async () => {
  testEnv = await createTestEnvironment('results');
});

after(async () => {
  await testEnv?.cleanup();
});

const GAME_ID = 'game-1';

/**
 * A match that has already been played.
 *
 * `scheduledTime` is in the past because the rule refuses a report before
 * tip-off, and it is seeded past the rules because the *create* rule refuses a
 * tip-off in the past. Reports are absent rather than null, per the collection's
 * absence-never-null convention.
 */
function playedGame(overrides = {}) {
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
    scheduledTime: secondsFromNow(-60 * 90),
    status: 'scheduled',
    arrivedPlayerIds: ['leader-home', 'leader-away'],
    createdBy: 'leader-away',
    createdAt: secondsFromNow(-60 * 90),
    // **Backdated, not a fresh server timestamp.** The report rule now floors
    // re-reports at five seconds since `updatedAt`, a burst-rate guard against
    // a leader toggling their own report to bounce the match between
    // `scheduled` and `disputed` — see `firestore.rules`. A game seeded with
    // `updatedAt` resolving to "now" would trip that floor the instant any
    // test reported against it, which is nearly all of them; this fixture
    // represents a match that has sat untouched since it was made, which is
    // also just the realistic default — nothing writes to a `seasonGames`
    // document between creation and a first report in the real app either.
    updatedAt: secondsFromNow(-60 * 90),
    ...overrides,
  };
}

async function seedGame(overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'seasonGames', GAME_ID), playedGame(overrides));
  });
}

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function gameRef(uid) {
  return doc(db(uid), 'seasonGames', GAME_ID);
}

/** One leader's report, shaped the way `SeasonGameService.reportResult` writes it. */
function report(field, winner, extra = {}) {
  return { [field]: winner, updatedAt: serverTimestamp(), ...extra };
}

/** The completing half: a report that also lands the derived result. */
function confirmingReport(field, winner, extra = {}) {
  return report(field, winner, {
    result: winner,
    status: 'confirmed',
    confirmedAt: serverTimestamp(),
    ...extra,
  });
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
  await seedGame();
});

// MARK: - Agreement confirms

test('two leaders agreeing confirms the match, and the second write is the one that lands the result', async () => {
  // The prompt's Phase 6 test case #2. Two *different* authenticated leaders.
  await assertSucceeds(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home')));

  const afterFirst = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(afterFirst.status, 'scheduled', 'one report settles nothing');
  assert.equal(afterFirst.result, undefined);

  await assertSucceeds(
    updateDoc(gameRef('leader-away'), confirmingReport('awayReport', 'squad-home'))
  );

  const confirmed = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(confirmed.status, 'confirmed');
  assert.equal(confirmed.result, 'squad-home');
  assert.equal(confirmed.homeReport, 'squad-home');
  assert.equal(confirmed.awayReport, 'squad-home');
  assert.ok(confirmed.confirmedAt, 'confirmedAt is pinned to request.time, not requested');
});

test('the order the two leaders report in does not matter', async () => {
  await assertSucceeds(updateDoc(gameRef('leader-away'), report('awayReport', 'squad-away')));
  await assertSucceeds(
    updateDoc(gameRef('leader-home'), confirmingReport('homeReport', 'squad-away'))
  );

  const confirmed = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(confirmed.status, 'confirmed');
  assert.equal(confirmed.result, 'squad-away');
});

test('a leader may report a win for the other squad — reporting is not claiming', async () => {
  await assertSucceeds(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-away')));
  await assertSucceeds(
    updateDoc(gameRef('leader-away'), confirmingReport('awayReport', 'squad-away'))
  );

  assert.equal((await readRaw(testEnv, `seasonGames/${GAME_ID}`)).result, 'squad-away');
});

test('an optional score rides along with a report and never touches the result', async () => {
  await assertSucceeds(
    updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home', {
      homeScore: 21,
      awayScore: 18,
    }))
  );

  const game = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(game.homeScore, 21);
  assert.equal(game.awayScore, 18);
  assert.equal(game.status, 'scheduled', 'a score is not a report of who won');
});

test('a negative or non-integer score is refused', async () => {
  await assertFails(
    updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home', { homeScore: -1 }))
  );
  await assertFails(
    updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home', { homeScore: '21' }))
  );
});

// MARK: - Disagreement disputes, and counts for nobody

test('two leaders naming different winners disputes the match and sets no result', async () => {
  // The prompt's Phase 6 test case #1.
  await assertSucceeds(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home')));

  // The away leader cannot confirm their own claim — the rule checks `result`
  // against *both* stored reports, and these two don't agree.
  await assertFails(
    updateDoc(gameRef('leader-away'), confirmingReport('awayReport', 'squad-away'))
  );

  // The honest write for the same disagreement is `disputed` with no result.
  await assertSucceeds(
    updateDoc(gameRef('leader-away'), report('awayReport', 'squad-away', { status: 'disputed' }))
  );

  const disputed = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(disputed.status, 'disputed');
  assert.equal(disputed.result, undefined, 'a disputed match counts for nobody');
  assert.equal(disputed.confirmedAt, undefined);
});

test('a disagreement cannot be written as still scheduled', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));

  // Status is derived, never chosen: two reports that disagree are `disputed`
  // and nothing else.
  await assertFails(updateDoc(gameRef('leader-away'), report('awayReport', 'squad-away')));
});

test('an agreement cannot be written as disputed either — the derivation runs both ways', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));

  await assertFails(
    updateDoc(gameRef('leader-away'), report('awayReport', 'squad-home', { status: 'disputed' }))
  );
});

// MARK: - The re-reporting floor is per-leader, not per-document

// `firestore.rules` explains the shape of this: nothing otherwise stops a
// leader clearing and re-entering their own report as fast as the network
// allows, bouncing the match between `scheduled` and `disputed` and churning
// the opponent's listener on every cycle. The floor has to be scoped to one
// leader's own field rather than the document as a whole, or it breaks the
// feature's own happy path — the first test below is the reason why, made
// explicit rather than left as an accident of test ordering.

test('two different leaders reporting for the first time within moments of each other is never floored', async () => {
  // The ordinary case mutual confirmation exists for: two people standing on
  // the same court, both opening the app right after the final basket. A
  // document-wide floor on "was this touched recently, by anyone" would
  // refuse the second leader's first-ever report for arriving promptly —
  // which is exactly what a first version of this floor did before this test
  // caught it. Nothing here waits; both writes land back-to-back on purpose.
  await assertSucceeds(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home')));
  await assertSucceeds(
    updateDoc(gameRef('leader-away'), confirmingReport('awayReport', 'squad-home'))
  );

  const confirmed = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(confirmed.status, 'confirmed');
});

test('a leader re-touching their own already-present report within five seconds is refused', async () => {
  // Unlike the test above, this is the *same* leader's field, already on the
  // document — the shape actually worth slowing down.
  await seedGame({ homeReport: 'squad-home', updatedAt: secondsFromNow(0) });

  await assertFails(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-away')));
});

test('a leader may re-touch their own report once five seconds have passed', async () => {
  await seedGame({ homeReport: 'squad-home', updatedAt: secondsFromNow(-6) });

  await assertSucceeds(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-away')));
});

// MARK: - Re-reporting is the same path, called again

test('a disputed match is resolved by one leader re-reporting to agree', async () => {
  // The design's own stated recovery path from a dispute. If
  // the rule only permitted absent → present, this write would be refused and a
  // disputed match would stay disputed forever.
  await seedGame({
    homeReport: 'squad-home',
    awayReport: 'squad-away',
    status: 'disputed',
  });

  await assertSucceeds(
    updateDoc(gameRef('leader-home'), confirmingReport('homeReport', 'squad-away'))
  );

  const confirmed = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(confirmed.status, 'confirmed');
  assert.equal(confirmed.result, 'squad-away');
});

test('a leader may clear their own report, which returns the match to awaiting one', async () => {
  await seedGame({
    homeReport: 'squad-home',
    awayReport: 'squad-away',
    status: 'disputed',
  });

  await assertSucceeds(
    updateDoc(gameRef('leader-away'), {
      awayReport: deleteField(),
      status: 'scheduled',
      updatedAt: serverTimestamp(),
    })
  );

  const cleared = await readRaw(testEnv, `seasonGames/${GAME_ID}`);
  assert.equal(cleared.status, 'scheduled');
  assert.equal(cleared.awayReport, undefined);
  assert.equal(cleared.homeReport, 'squad-home', "the other leader's report is untouched");
});

test('a confirmed match cannot be re-reported — agreement is not unilaterally revocable', async () => {
  await seedGame({
    homeReport: 'squad-away',
    awayReport: 'squad-away',
    result: 'squad-away',
    status: 'confirmed',
    confirmedAt: secondsFromNow(-60),
  });

  // The losing leader trying to turn a settled loss back into a dispute.
  await assertFails(
    updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home', { status: 'disputed' }))
  );

  assert.equal((await readRaw(testEnv, `seasonGames/${GAME_ID}`)).result, 'squad-away');
});

test('a cancelled match cannot be reported', async () => {
  await seedGame({ status: 'cancelled', cancelledBySquadId: 'squad-home' });

  await assertFails(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home')));
});

// MARK: - Each report field is pinned to its own leader

test('neither leader may write the other’s report field, in either direction', async () => {
  await assertFails(
    updateDoc(gameRef('leader-home'), report('awayReport', 'squad-home')),
    'the home leader must not be able to write awayReport'
  );

  await assertFails(
    updateDoc(gameRef('leader-away'), report('homeReport', 'squad-away')),
    'the away leader must not be able to write homeReport'
  );
});

test('a leader cannot write both reports at once and confirm the pair alone', async () => {
  // The single most valuable thing this rule refuses: one client manufacturing
  // the agreement that mutual confirmation is entirely made of.
  await assertFails(
    updateDoc(gameRef('leader-home'), {
      homeReport: 'squad-home',
      awayReport: 'squad-home',
      result: 'squad-home',
      status: 'confirmed',
      confirmedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    })
  );

  assert.equal((await readRaw(testEnv, `seasonGames/${GAME_ID}`)).status, 'scheduled');
});

test('a member who is not a leader cannot report', async () => {
  await assertFails(updateDoc(gameRef('member-home'), report('homeReport', 'squad-home')));
  await assertFails(updateDoc(gameRef('member-away'), report('awayReport', 'squad-away')));
});

test('someone on neither squad cannot report', async () => {
  await assertFails(updateDoc(gameRef('stranger'), report('homeReport', 'squad-home')));
});

// MARK: - `result` is never taken on trust

test('a result no report names is refused', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));

  await assertFails(
    updateDoc(gameRef('leader-away'), report('awayReport', 'squad-home', {
      result: 'squad-away',
      status: 'confirmed',
      confirmedAt: serverTimestamp(),
    })),
    'result must equal both reports, not merely be a squad in the match'
  );
});

test('a single report cannot carry a result, however well-formed', async () => {
  await assertFails(
    updateDoc(gameRef('leader-home'), confirmingReport('homeReport', 'squad-home')),
    'one leader saying so is not mutual confirmation'
  );
});

test('a report naming a squad that is not in this match is refused', async () => {
  await assertFails(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-elsewhere')));
});

test('confirmedAt is pinned to request.time, not chosen', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));

  await assertFails(
    updateDoc(gameRef('leader-away'), report('awayReport', 'squad-home', {
      result: 'squad-home',
      status: 'confirmed',
      confirmedAt: secondsFromNow(-60 * 60 * 24),
    }))
  );
});

test('updatedAt is pinned too', async () => {
  await assertFails(
    updateDoc(gameRef('leader-home'), {
      homeReport: 'squad-home',
      updatedAt: secondsFromNow(-60),
    })
  );
});

// MARK: - One write, one path

test('a report cannot smuggle a cancellation, an arrival, or a reschedule', async () => {
  for (const extra of [
    { status: 'cancelled', cancelledBySquadId: 'squad-home' },
    { arrivedPlayerIds: ['leader-home', 'leader-away', 'member-home'] },
    { courtId: 'court-9' },
    { scheduledTime: secondsFromNow(60 * 60) },
    { homeLeaderId: 'leader-away' },
    { homeSquadName: 'Somebody Else' },
  ]) {
    await assertFails(
      updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home', extra)),
      `a report carrying ${Object.keys(extra)[0]} must be refused`
    );
  }
});

test('a bare updatedAt bump is not a report', async () => {
  // Without the `hasAll` guard this path would be a general-purpose write on a
  // match the caller happens to lead.
  await assertFails(updateDoc(gameRef('leader-home'), { updatedAt: serverTimestamp() }));
});

// MARK: - A match cannot be reported before it is played

test('reporting before tip-off is refused', async () => {
  await seedGame({ scheduledTime: secondsFromNow(60 * 60) });

  await assertFails(updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home')));
});

// MARK: - The record the whole design exists to produce

test('a confirmed match is readable by anyone, which is what makes a record checkable', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));
  await updateDoc(gameRef('leader-away'), confirmingReport('awayReport', 'squad-home'));

  const { collection, getDocs, query, where } = await import('firebase/firestore');

  // The derived-record query, run by a squad that is in neither match — an
  // opponent checking a record is the reason `seasonGames` is world-readable.
  const snapshot = await getDocs(
    query(
      collection(db('nobody'), 'seasonGames'),
      where('squadIds', 'array-contains', 'squad-home'),
      where('status', '==', 'confirmed')
    )
  );

  assert.equal(snapshot.size, 1);
  assert.equal(snapshot.docs[0].data().result, 'squad-home');
});

test('a disputed match is invisible to the record query, so it moves nobody', async () => {
  await updateDoc(gameRef('leader-home'), report('homeReport', 'squad-home'));
  await updateDoc(
    gameRef('leader-away'),
    report('awayReport', 'squad-away', { status: 'disputed' })
  );

  const { collection, getDocs, query, where } = await import('firebase/firestore');

  const snapshot = await getDocs(
    query(
      collection(db('leader-home'), 'seasonGames'),
      where('squadIds', 'array-contains', 'squad-home'),
      where('status', '==', 'confirmed')
    )
  );

  assert.equal(snapshot.size, 0);
});
