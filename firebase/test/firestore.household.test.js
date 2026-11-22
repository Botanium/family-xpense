// WP-12: the household the phone founds, and membership only the server
// changes (BACKLOG S1.4, S1.5; DATA_MODEL 2.2, 2.3, 2.15, 5).
//
// The founding batch below has the shape `FirebaseHouseholdRepository.create`
// writes (app/lib/data/household_repository_firebase.dart). The partner is
// added the way the server's join flow does it, with admin rights
// (server/lib/household/household_service.dart).
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { ALICE, EVE, createEnv, seed, serverTime } from './setup.js';

let env;
const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
const { arrayUnion, arrayRemove } = firebase.firestore.FieldValue;

const NEW = 'h-new';

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(env); });

function stamps(uid) {
  return { createdAt: serverTime(), createdBy: uid, updatedAt: serverTime(), updatedBy: uid, schemaVersion: 1 };
}

/** The app's founding batch for `uid`: household, owner, categories, profile. */
function foundingBatch(d, uid, { hid = NEW, baseCurrency = 'USD', memberIds = [uid] } = {}) {
  const h = d.collection('households').doc(hid);
  const batch = d.batch();
  batch.set(h, {
    name: 'Our home', baseCurrency, timeZone: 'Asia/Baghdad', memberIds,
    rateKind: 'market', rateAskedOn: null, cloudInsights: true, weekStart: 'sat',
    moneySchema: 1, ...stamps(uid),
  });
  batch.set(h.collection('members').doc(uid), {
    displayName: 'Eve', initial: 'E', role: 'owner', privacyMode: 'smart',
    notificationPrefs: {}, joinedAt: serverTime(), ...stamps(uid),
  });
  const categories = [
    ['food', 'expense', null], ['groceries', 'expense', 'food'], ['dining', 'expense', 'food'],
    ['salary', 'income', null], ['other_expense', 'expense', null], ['other_income', 'income', null],
  ];
  categories.forEach(([slug, kind, parentId], order) => {
    batch.set(h.collection('categories').doc(slug), {
      slug, names: { en: slug }, kind, parentId, colorKey: null, iconKey: null,
      order, system: true, archived: false, ...stamps(uid),
    });
  });
  batch.set(d.doc(`users/${uid}`), { householdId: hid, displayName: 'Eve', locale: 'en' }, { merge: true });
  return batch;
}

/** What the server's join flow writes for `uid`, with admin rights. */
async function serverJoins(uid, hid = NEW, memberIds) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    const batch = admin.batch();
    batch.set(admin.doc(`households/${hid}`), { memberIds }, { merge: true });
    batch.set(admin.doc(`households/${hid}/members/${uid}`), { displayName: 'Bo', initial: 'B', role: 'partner', privacyMode: 'smart' });
    batch.set(admin.doc(`users/${uid}`), { householdId: hid }, { merge: true });
    await batch.commit();
  });
}

describe('creating a household from the phone (S1.4)', () => {
  it('the app\'s founding batch succeeds in USD and in IQD', async () => {
    await assertSucceeds(foundingBatch(db(EVE), EVE).commit());
    await assertSucceeds(foundingBatch(db('zoe'), 'zoe', { hid: 'h-iqd', baseCurrency: 'IQD' }).commit());
    // The founder can read what they made.
    await assertSucceeds(db(EVE).doc(`households/${NEW}`).get());
    await assertSucceeds(db(EVE).collection(`households/${NEW}/categories`).get());
  });

  it('the batch cannot list anyone but the founder', async () => {
    await assertFails(foundingBatch(db(EVE), EVE, { memberIds: [EVE, ALICE] }).commit());
    await assertFails(foundingBatch(db(EVE), EVE, { memberIds: [ALICE] }).commit());
    await assertFails(foundingBatch(db(EVE), EVE, { memberIds: [] }).commit());
  });

  it('an existing household cannot be founded again', async () => {
    await assertSucceeds(foundingBatch(db(EVE), EVE).commit());
    // Not by its owner: the categories exist, and their createdAt is fixed
    // once written ...
    await assertFails(foundingBatch(db(EVE), EVE).commit());
    // ... and not by someone else taking it over.
    await assertFails(foundingBatch(db('mallory'), 'mallory').commit());
  });
});

describe('the phone cannot change memberIds (S1.5)', () => {
  beforeEach(async () => {
    await foundingBatch(db(EVE), EVE).commit();
  });

  it('the founder cannot add a partner, by value or with arrayUnion', async () => {
    const h = db(EVE).doc(`households/${NEW}`);
    await assertFails(h.update({ memberIds: [EVE, 'sam'] }));
    await assertFails(h.update({ memberIds: arrayUnion('sam') }));
    await assertFails(h.set({ memberIds: [EVE, 'sam'] }, { merge: true }));
  });

  it('the founder cannot remove themself or empty the list', async () => {
    const h = db(EVE).doc(`households/${NEW}`);
    await assertFails(h.update({ memberIds: arrayRemove(EVE) }));
    await assertFails(h.update({ memberIds: [] }));
  });

  it('someone with the invite but no join cannot add themself', async () => {
    const sam = db('sam');
    const h = sam.doc(`households/${NEW}`);
    await assertFails(h.update({ memberIds: arrayUnion('sam') }));
    await assertFails(h.set({ memberIds: [EVE, 'sam'] }, { merge: true }));
    // Writing their own member document or pointing their profile at the
    // household does not make them a member either.
    await assertFails(h.collection('members').doc('sam').set({ displayName: 'Sam', role: 'partner' }));
    await assertSucceeds(sam.doc('users/sam').set({ householdId: NEW }, { merge: true }));
    await assertFails(h.get());
    await assertFails(h.collection('categories').get());
  });

  it('after the server adds the partner, neither member can change the list', async () => {
    await serverJoins('sam', NEW, [EVE, 'sam']);
    await assertSucceeds(db('sam').doc(`households/${NEW}`).get());

    for (const uid of [EVE, 'sam']) {
      const h = db(uid).doc(`households/${NEW}`);
      await assertFails(h.update({ memberIds: [EVE, 'sam', 'third'] }), uid);
      await assertFails(h.update({ memberIds: arrayUnion('third') }), uid);
      await assertFails(h.update({ memberIds: arrayRemove(uid === EVE ? 'sam' : EVE) }), uid);
      await assertFails(h.update({ memberIds: [uid] }), uid);
    }
    // The other household fields stay editable by members (name, stamps).
    await assertSucceeds(db('sam').doc(`households/${NEW}`).update({ name: 'Home', updatedAt: serverTime(), updatedBy: 'sam' }));
  });

  it('the partner cannot make themself owner', async () => {
    await serverJoins('sam', NEW, [EVE, 'sam']);
    await assertFails(db('sam').doc(`households/${NEW}/members/sam`).update({ role: 'owner' }));
  });
});

describe('invites and rate limits are server-only (DATA_MODEL 2.15)', () => {
  it('no phone reads or writes invites/{codeHash} or rateLimits/{uid}', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('rateLimits/eve').set({ householdJoin: { count: 3 } });
    });
    for (const uid of [EVE, ALICE]) {
      const d = db(uid);
      await assertFails(d.doc('invites/abc123').get());
      await assertFails(d.collection('invites').where('hid', '==', 'h1').get());
      await assertFails(d.doc('invites/abc123').update({ usedBy: uid }));
      await assertFails(d.doc('invites/new').set({ hid: 'h1', createdBy: uid }));
      await assertFails(d.doc(`rateLimits/${uid}`).get());
      await assertFails(d.doc(`rateLimits/${uid}`).set({ householdJoin: { count: 0 } }));
    }
  });
});
