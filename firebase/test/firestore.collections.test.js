// At least one allowed and one denied case per collection, plus the
// collection-specific checks the rules add on top of the shared pattern.
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import {
  ALICE, BOB, EVE, HID, TODAY, VISIBLE_COLLECTIONS,
  accountDoc, createEnv, createdBy, hh, seed, serverTime, txnDoc, updatedBy,
} from './setup.js';

let env;
const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(env); });

describe('users', () => {
  it('a user reads and writes only their own profile and devices', async () => {
    await assertSucceeds(db(ALICE).doc(`users/${ALICE}`).get());
    await assertSucceeds(db(ALICE).doc(`users/${ALICE}`).update({ locale: 'en' }));
    await assertSucceeds(db(ALICE).doc(`users/${ALICE}/devices/d2`).set({ platform: 'ios' }));
    await assertFails(db(BOB).doc(`users/${ALICE}`).get());
    await assertFails(db(BOB).doc(`users/${ALICE}`).update({ householdId: 'h2' }));
    await assertFails(db(BOB).doc(`users/${ALICE}/devices/d1`).get());
    await assertFails(db(null).doc(`users/${ALICE}`).get());
  });
});

describe('households', () => {
  it('members get it; non-members do not', async () => {
    await assertSucceeds(hh(db(BOB)).get());
    await assertFails(hh(db(EVE)).get());
  });

  it('creation needs a supported base currency', async () => {
    await assertFails(db(EVE).doc('households/h3').set({ name: 'X', baseCurrency: 'EUR', memberIds: [EVE] }));
    await assertFails(db(null).doc('households/h4').set({ name: 'X', baseCurrency: 'IQD', memberIds: [] }));
  });

  it('the founding batch writes the household, the owner\'s member document and the default categories', async () => {
    const d = db(EVE);
    const h = d.collection('households').doc('h3');
    const batch = d.batch();
    batch.set(h, { name: 'Eve home', baseCurrency: 'IQD', memberIds: [EVE], moneySchema: 1, cloudInsights: true });
    batch.set(h.collection('members').doc(EVE), { displayName: 'Eve', initial: 'E', role: 'owner', privacyMode: 'smart', joinedAt: serverTime() });
    batch.set(h.collection('categories').doc('groceries'), { slug: 'groceries', names: { en: 'Groceries' }, kind: 'expense', system: true, archived: false, ...createdBy(EVE) });
    batch.set(h.collection('categories').doc('salary'), { slug: 'salary', names: { en: 'Salary' }, kind: 'income', system: true, archived: false, ...createdBy(EVE) });
    batch.set(d.doc(`users/${EVE}`), { displayName: 'Eve', locale: 'en', householdId: 'h3' });
    await assertSucceeds(batch.commit());
  });

  it('the founding batch cannot create a member document for someone else or as partner', async () => {
    const d = db(EVE);
    const h = d.collection('households').doc('h3');
    const b1 = d.batch();
    b1.set(h, { name: 'X', baseCurrency: 'IQD', memberIds: [EVE] });
    b1.set(h.collection('members').doc(ALICE), { displayName: 'Alice', role: 'owner' });
    await assertFails(b1.commit());
    const b2 = d.batch();
    b2.set(h, { name: 'X', baseCurrency: 'IQD', memberIds: [EVE] });
    b2.set(h.collection('members').doc(EVE), { displayName: 'Eve', role: 'partner' });
    await assertFails(b2.commit());
  });

  it('a member document or category cannot be planted without the household in the same batch', async () => {
    const h = db(EVE).collection('households').doc('h9');
    await assertFails(h.collection('members').doc(EVE).set({ displayName: 'Eve', role: 'owner' }));
    await assertFails(h.collection('categories').doc('x').set({ slug: 'x', ...createdBy(EVE) }));
    // An existing household cannot be "founded" again.
    await assertFails(hh(db(EVE)).collection('categories').doc('x').set({ slug: 'x', ...createdBy(EVE) }));
  });
});

describe('members', () => {
  it('members read each other; a member edits only their own document, not their role', async () => {
    await assertSucceeds(hh(db(BOB)).collection('members').get());
    await assertSucceeds(hh(db(BOB)).collection('members').doc(BOB).update({ privacyMode: 'on_device' }));
    await assertFails(hh(db(BOB)).collection('members').doc(ALICE).update({ privacyMode: 'cloud' }));
    await assertFails(hh(db(BOB)).collection('members').doc(BOB).update({ role: 'owner' }));
  });
});

describe('accounts', () => {
  const acc = (uid) => hh(db(uid)).collection('accounts');

  it('a member creates a joint account visible to both, or a personal one they own', async () => {
    await assertSucceeds(acc(BOB).doc('j2').set(accountDoc({ ...createdBy(BOB) })));
    await assertSucceeds(acc(BOB).doc('p2').set(accountDoc({ scope: 'personal', ownerUid: BOB, visibleTo: [BOB], ...createdBy(BOB) })));
  });

  it('a personal account cannot be created for the partner, and a joint one must include everyone', async () => {
    await assertFails(acc(BOB).doc('x').set(accountDoc({ scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE, BOB], ...createdBy(BOB) })));
    await assertFails(acc(BOB).doc('y').set(accountDoc({ visibleTo: [BOB], ...createdBy(BOB) })));
    await assertFails(acc(BOB).doc('z').set(accountDoc({ currency: 'EUR', ...createdBy(BOB) })));
  });

  it('create needs correct audit stamps', async () => {
    await assertFails(acc(BOB).doc('s1').set(accountDoc({ ...createdBy(BOB), createdBy: ALICE })));
    await assertFails(acc(BOB).doc('s2').set(accountDoc({ ...createdBy(BOB), updatedAt: new Date('2020-01-01') })));
    await assertFails(acc(BOB).doc('s3').set(accountDoc({ name: 'No stamps' })));
  });

  it('the owner can stop sharing; the partner cannot change sharing or lock the owner out', async () => {
    await assertFails(acc(BOB).doc('aShared').update({ visibleTo: [BOB], ...updatedBy(BOB) }));
    await assertFails(acc(BOB).doc('aShared').update({ sharedWithPartner: false, ...updatedBy(BOB) }));
    await assertFails(acc(BOB).doc('joint').update({ visibleTo: [BOB], ...updatedBy(BOB) }));
    await assertSucceeds(acc(BOB).doc('aShared').update({ name: 'Alice dollars', ...updatedBy(BOB) }));
    await assertSucceeds(acc(ALICE).doc('aShared').update({ sharedWithPartner: false, visibleTo: [ALICE], ...updatedBy(ALICE) }));
    await assertFails(acc(BOB).doc('aShared').get());
  });

  it('currency and owner are immutable; updates need fresh stamps', async () => {
    await assertFails(acc(ALICE).doc('aPriv').update({ currency: 'USD', ...updatedBy(ALICE) }));
    await assertFails(acc(ALICE).doc('aPriv').update({ ownerUid: BOB, visibleTo: [ALICE, BOB], ...updatedBy(ALICE) }));
    await assertFails(acc(ALICE).doc('aPriv').update({ name: 'No stamp' }));
    await assertFails(acc(ALICE).doc('aPriv').update({ name: 'Wrong user', ...updatedBy(BOB) }));
    await assertFails(acc(ALICE).doc('aPriv').update({ createdBy: BOB, ...updatedBy(ALICE) }));
    await assertSucceeds(acc(ALICE).doc('aPriv').update({ archived: true, ...updatedBy(ALICE) }));
  });

  it('a partner cannot write a private account', async () => {
    await assertFails(acc(BOB).doc('aPriv').update({ name: 'Mine now', ...updatedBy(BOB) }));
  });
});

describe('transactions', () => {
  const tx = (uid) => hh(db(uid)).collection('transactions');

  it('a valid expense on a visible account is accepted', async () => {
    await assertSucceeds(tx(BOB).doc('n1').set(txnDoc({ whoUid: BOB, ...createdBy(BOB) })));
    await assertSucceeds(tx(ALICE).doc('n2').set(txnDoc({ accountId: 'aPriv', visibleTo: [ALICE], ...createdBy(ALICE) })));
  });

  it('a partner cannot post to a private account they cannot see', async () => {
    await assertFails(tx(BOB).doc('n1').set(txnDoc({ accountId: 'aPriv', visibleTo: [ALICE, BOB], ...createdBy(BOB) })));
    await assertFails(tx(BOB).doc('n2').set(txnDoc({ accountId: 'aPriv', visibleTo: [BOB], ...createdBy(BOB) })));
  });

  it('visibleTo must equal the union of the accounts\' visibleTo', async () => {
    // Hiding a joint expense from the partner.
    await assertFails(tx(ALICE).doc('n1').set(txnDoc({ visibleTo: [ALICE], ...createdBy(ALICE) })));
    // Exposing a private expense.
    await assertFails(tx(ALICE).doc('n2').set(txnDoc({ accountId: 'aPriv', visibleTo: [ALICE, BOB], ...createdBy(ALICE) })));
    // A transfer from a private account into a joint one is visible to both.
    const transfer = { type: 'transfer', accountId: 'aPriv', toAccountId: 'joint', categoryId: null };
    await assertSucceeds(tx(ALICE).doc('n3').set(txnDoc({ ...transfer, visibleTo: [ALICE, BOB], ...createdBy(ALICE) })));
    await assertFails(tx(ALICE).doc('n4').set(txnDoc({ ...transfer, visibleTo: [ALICE], ...createdBy(ALICE) })));
    // Nobody can transfer into the partner's private account.
    await assertFails(tx(ALICE).doc('n5').set(txnDoc({ ...transfer, accountId: 'joint', toAccountId: 'bPriv', visibleTo: [ALICE, BOB], ...createdBy(ALICE) })));
  });

  it('amounts are positive integers, the type and currency are known and match the account', async () => {
    const bad = [
      { amountMinor: 0 }, { amountMinor: -5 }, { amountMinor: 10.5 }, { amountMinor: '100' },
      { baseAmountMinor: 1.25 }, { type: 'gift' }, { currency: 'EUR' }, { currency: 'USD' },
      { accountId: 'missing' }, { deletedAt: new Date() },
    ];
    for (const [i, fields] of bad.entries()) {
      await assertFails(tx(ALICE).doc(`bad${i}`).set(txnDoc({ ...fields, ...createdBy(ALICE) })), `case ${JSON.stringify(fields)}`);
    }
  });

  it('edits keep the amount a positive integer and keep createdBy', async () => {
    await assertFails(tx(ALICE).doc('tJoint').update({ amountMinor: -1, rev: 4, ...updatedBy(ALICE) }));
    await assertFails(tx(ALICE).doc('tJoint').update({ createdBy: BOB, rev: 4, ...updatedBy(ALICE) }));
    await assertSucceeds(tx(ALICE).doc('tJoint').update({ amountMinor: 12000, rev: 4, ...updatedBy(ALICE) }));
  });

  it('moving an entry to another account or changing its visibleTo re-checks the accounts', async () => {
    // Bob cannot move a joint entry into alice's private account.
    await assertFails(tx(BOB).doc('tJoint').update({ accountId: 'aPriv', visibleTo: [ALICE, BOB], rev: 4, ...updatedBy(BOB) }));
    // Alice cannot hide a joint entry from bob.
    await assertFails(tx(ALICE).doc('tJoint').update({ visibleTo: [ALICE], rev: 4, ...updatedBy(ALICE) }));
    // Nor move it to a USD account without changing its currency.
    await assertFails(tx(ALICE).doc('tJoint').update({ accountId: 'aShared', rev: 4, ...updatedBy(ALICE) }));
    // Alice may move it into her private account, which makes it private.
    await assertSucceeds(tx(ALICE).doc('tJoint').update({ accountId: 'aPriv', visibleTo: [ALICE], rev: 4, ...updatedBy(ALICE) }));
  });

  it('edits keep every ledger invariant (Codex review)', async () => {
    const bad = [
      { baseAmountMinor: '10000' }, { baseAmountMinor: firebase.firestore.FieldValue.delete() },
      { baseAmountMinor: 1.5 }, { type: 'gift' }, { type: firebase.firestore.FieldValue.delete() },
      { amountMinor: firebase.firestore.FieldValue.delete() }, { accountId: firebase.firestore.FieldValue.delete() },
    ];
    for (const fields of bad) {
      await assertFails(tx(BOB).doc('tJoint').update({ ...fields, rev: 4, ...updatedBy(BOB) }));
    }
    await assertSucceeds(tx(BOB).doc('tJoint').update({ type: 'income', baseAmountMinor: 9000, rev: 4, ...updatedBy(BOB) }));
  });

  it('an edit must name the version it was built on (prevRevId, Codex review PR #35)', async () => {
    // Legacy entry without revId: the first chained edit names none.
    await assertFails(tx(ALICE).doc('tJoint').update({ title: 'A', rev: 4, revId: 'r4', prevRevId: 'r3', ...updatedBy(ALICE) }));
    await assertSucceeds(tx(ALICE).doc('tJoint').update({ title: 'A', rev: 4, revId: 'r4', prevRevId: null, ...updatedBy(ALICE) }));
    // Bob's write lands first (rev 5 on r4).
    await assertSucceeds(tx(BOB).doc('tJoint').update({ note: 'B', rev: 5, revId: 'b5', prevRevId: 'r4', ...updatedBy(BOB) }));
    // Alice's queued edit built on r4 is refused; so is her queued delete
    // built on that edit, although its rev number lines up.
    await assertFails(tx(ALICE).doc('tJoint').update({ amountMinor: 200, rev: 5, revId: 'a5', prevRevId: 'r4', ...updatedBy(ALICE) }));
    await assertFails(tx(ALICE).doc('tJoint').update({ deletedAt: serverTime(), rev: 6, revId: 'a6', prevRevId: 'a5', ...updatedBy(ALICE) }));
    // Leaving the chain fields as they are names the wrong predecessor.
    await assertFails(tx(ALICE).doc('tJoint').update({ title: 'C', rev: 6, ...updatedBy(ALICE) }));
    // Built on Bob's version it is accepted.
    await assertSucceeds(tx(ALICE).doc('tJoint').update({ amountMinor: 200, rev: 6, revId: 'a6', prevRevId: 'b5', ...updatedBy(ALICE) }));
  });

  it('a save batch fits the rules read budget up to 15 distinct accounts (Codex review PR #35)', async () => {
    // The app's batch: one entry per account plus its balance increment.
    // Each account is one rules read, the household one more, and a batch
    // may read 20 documents; the app caps a save at 15 accounts and loans.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const h = hh(ctx.firestore());
      for (let i = 0; i < 20; i++) await h.collection('accounts').doc(`r${i}`).set(accountDoc({ order: i }));
    });
    const save = (count, prefix) => {
      const d = db(ALICE);
      const batch = d.batch();
      for (let i = 0; i < count; i++) {
        batch.set(hh(d).collection('transactions').doc(`${prefix}${i}`), txnDoc({ accountId: `r${i}`, revId: `${prefix}${i}`, prevRevId: null, ...createdBy(ALICE) }));
        batch.update(hh(d).collection('accounts').doc(`r${i}`), { balanceMinor: firebase.firestore.FieldValue.increment(-10000), ...updatedBy(ALICE) });
      }
      return batch.commit();
    };
    await assertSucceeds(save(15, 'ok'));
    // 20 accounts and the household are 21 distinct documents.
    await assertFails(save(20, 'big'));
  });

  it('a partner cannot edit or soft-delete a private transaction', async () => {
    await assertFails(tx(BOB).doc('tPriv').update({ deletedAt: new Date(), rev: 1, ...updatedBy(BOB) }));
  });
});

describe('revisions', () => {
  const revs = (uid, t) => hh(db(uid)).collection('transactions').doc(t).collection('revisions');

  it('an edit and its revision are written in one batch by a member who can see the transaction', async () => {
    const d = db(BOB);
    const t = hh(d).collection('transactions').doc('tJoint');
    const batch = d.batch();
    batch.update(t, { title: 'Dinner', rev: 4, ...updatedBy(BOB) });
    batch.set(t.collection('revisions').doc('4'), { rev: 4, before: { title: 'Lunch' }, changedBy: BOB, changedAt: serverTime(), reason: 'edit' });
    await assertSucceeds(batch.commit());
    await assertSucceeds(revs(ALICE, 'tJoint').get());
  });

  it('revisions are append-only and cannot be forged', async () => {
    await assertFails(revs(BOB, 'tJoint').doc('1').update({ reason: 'undo' }));
    await assertFails(revs(BOB, 'tJoint').doc('9').set({ rev: 9, changedBy: ALICE, changedAt: serverTime(), reason: 'edit' }));
    await assertFails(revs(BOB, 'tPriv').doc('9').set({ rev: 9, changedBy: BOB, changedAt: serverTime(), reason: 'edit' }));
  });
});

describe('loans, goals, budgets, recurring, rules, people', () => {
  for (const [coll, body] of Object.entries(VISIBLE_COLLECTIONS)) {
    it(`${coll}: a member creates and edits what they can see`, async () => {
      const c = hh(db(BOB)).collection(coll);
      await assertSucceeds(c.doc('n1').set({ ...body, scope: 'joint', ownerUid: null, visibleTo: [ALICE, BOB], ...createdBy(BOB) }));
      await assertSucceeds(c.doc('n2').set({ ...body, scope: 'personal', ownerUid: BOB, visibleTo: [BOB], ...createdBy(BOB) }));
      await assertSucceeds(c.doc('shared').update({ updatedBy: BOB, updatedAt: serverTime() }));
    });

    it(`${coll}: a partner cannot edit or take over a private document`, async () => {
      const c = hh(db(BOB)).collection(coll);
      await assertFails(c.doc('private').update({ ...updatedBy(BOB) }));
      await assertFails(c.doc('private').set({ ...body, visibleTo: [BOB], ...createdBy(BOB) }));
      await assertFails(c.doc('n3').set({ ...body, visibleTo: [ALICE], ...createdBy(BOB) }));
    });
  }

  for (const coll of Object.keys(VISIBLE_COLLECTIONS)) {
    it(`${coll}: a partner cannot take ownership of a shared personal document (Codex review)`, async () => {
      await env.withSecurityRulesDisabled((ctx) => hh(ctx.firestore()).collection(coll).doc('alicesShared')
        .set({ ...VISIBLE_COLLECTIONS[coll], scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE, BOB] }));
      const d = hh(db(BOB)).collection(coll).doc('alicesShared');
      await assertFails(d.update({ ownerUid: BOB, ...updatedBy(BOB) }));
      await assertFails(d.update({ visibleTo: [BOB], ...updatedBy(BOB) }));
      await assertFails(d.update({ ownerUid: BOB, visibleTo: [BOB], ...updatedBy(BOB) }));
      await assertSucceeds(d.update({ note: 'edited by bob', ...updatedBy(BOB) }));
      await assertSucceeds(hh(db(ALICE)).collection(coll).doc('alicesShared').update({ visibleTo: [ALICE], ...updatedBy(ALICE) }));
    });
  }

  it('loans follow the account model: the owner stays in visibleTo and joint loans include everyone', async () => {
    const c = hh(db(BOB)).collection('loans');
    await assertFails(c.doc('shared').update({ visibleTo: [BOB], ...updatedBy(BOB) }));
    await assertFails(c.doc('x').set({ ...VISIBLE_COLLECTIONS.loans, scope: 'personal', ownerUid: ALICE, visibleTo: [BOB], ...createdBy(BOB) }));
  });
});

describe('categories', () => {
  it('members read and edit categories with stamps', async () => {
    const c = hh(db(BOB)).collection('categories');
    await assertSucceeds(c.get());
    await assertSucceeds(c.doc('pets').set({ slug: 'pets', names: { en: 'Pets' }, kind: 'expense', system: false, archived: false, ...createdBy(BOB) }));
    await assertSucceeds(c.doc('groceries').update({ archived: true, ...updatedBy(BOB) }));
  });

  it('non-members cannot write and stamps are required', async () => {
    await assertFails(hh(db(EVE)).collection('categories').doc('pets').set({ slug: 'pets', ...createdBy(EVE) }));
    await assertFails(hh(db(BOB)).collection('categories').doc('groceries').update({ archived: true }));
  });
});

describe('fxRates', () => {
  const fx = (uid) => hh(db(uid)).collection('fxRates');
  const rate = (uid, extra = {}) => ({ usdIqd: '1705', kind: 'market', enteredBy: uid, enteredAt: serverTime(), ...extra });

  it('a member enters the day\'s rate and either member can correct it', async () => {
    await assertSucceeds(fx(ALICE).doc(TODAY).set(rate(ALICE)));
    await assertSucceeds(fx(BOB).doc(TODAY).set(rate(BOB, { usdIqd: '1710.5', kind: 'official' })));
    await assertSucceeds(fx(BOB).where('kind', '==', 'market').get());
  });

  it('rates are attributed to the caller, stored as decimal strings and keyed by date', async () => {
    await assertFails(fx(ALICE).doc(TODAY).set(rate(BOB)));
    await assertFails(fx(ALICE).doc(TODAY).set(rate(ALICE, { usdIqd: 1705 })));
    await assertFails(fx(ALICE).doc(TODAY).set(rate(ALICE, { usdIqd: '1,705' })));
    await assertFails(fx(ALICE).doc(TODAY).set(rate(ALICE, { kind: 'manual' })));
    await assertFails(fx(ALICE).doc('today').set(rate(ALICE)));
    await assertFails(fx(EVE).doc(TODAY).set(rate(EVE)));
    await assertFails(fx(EVE).doc('2026-11-21').get());
  });
});

describe('notifications', () => {
  const n = (uid) => hh(db(uid)).collection('notifications');

  it('a target reads it and marks it read', async () => {
    await assertSucceeds(n(ALICE).doc('nAlice').get());
    await assertSucceeds(n(BOB).doc('nBoth').update({ readBy: [BOB] }));
  });

  it('a non-target cannot read it; only readBy changes, and only with one\'s own uid', async () => {
    await assertFails(n(BOB).doc('nAlice').get());
    await assertFails(n(BOB).doc('nAlice').update({ readBy: [BOB] }));
    await assertFails(n(BOB).doc('nBoth').update({ readBy: [ALICE, BOB] }));
    await assertFails(n(BOB).doc('nBoth').update({ readBy: [BOB], titleKey: 'x' }));
    await assertFails(n(BOB).doc('nBoth').update({ targetUids: [BOB] }));
  });
});
