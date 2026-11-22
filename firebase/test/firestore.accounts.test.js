// WP-13 (BACKLOG S1.6, S1.7, S1.8): a partner sees nothing of a private
// account in any list, and the exact writes the app's accounts repository
// makes (app/lib/data/accounts_repository_firebase.dart) are accepted.
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import {
  ALICE, BOB, TODAY, accountDoc, createEnv, createdBy, hh, seed, serverTime, updatedBy,
} from './setup.js';

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const inc = (n) => firebase.firestore.FieldValue.increment(n);

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(env); });

describe('a partner sees nothing of a private account', () => {
  it('not the account, by id or in any list', async () => {
    const acc = hh(db(BOB)).collection('accounts');
    await assertFails(acc.doc('aPriv').get());
    // The list the Accounts screen runs.
    const list = await assertSucceeds(acc.where('visibleTo', 'array-contains', BOB).orderBy('order').get());
    const ids = list.docs.map((d) => d.id).sort();
    assert.deepEqual(ids, ['aShared', 'bPriv', 'joint']);
    // Without the filter the query is refused, so no list can leak it.
    await assertFails(acc.get());
    await assertFails(acc.where('scope', '==', 'personal').get());
  });

  it('not its entries, in Activity or on the account', async () => {
    const tx = hh(db(BOB)).collection('transactions');
    await assertFails(tx.doc('tPriv').get());
    const visible = await assertSucceeds(tx.where('visibleTo', 'array-contains', BOB).get());
    assert.ok(!visible.docs.some((d) => d.id === 'tPriv'));
    // The account detail queries: filtered, they return nothing.
    const onAccount = await assertSucceeds(
      tx.where('visibleTo', 'array-contains', BOB).where('accountId', '==', 'aPriv').orderBy('occurredAt', 'desc').get(),
    );
    assert.equal(onAccount.size, 0);
    await assertFails(tx.where('accountId', '==', 'aPriv').get());
    await assertFails(tx.doc('tPriv').collection('revisions').get());
  });

  it('only a yes/no flag on the member document, never the accounts', async () => {
    await assertSucceeds(hh(db(ALICE)).collection('members').doc(ALICE).update({ hasPrivateAccounts: true }));
    const alice = await assertSucceeds(hh(db(BOB)).collection('members').doc(ALICE).get());
    assert.equal(alice.data().hasPrivateAccounts, true);
    await assertFails(hh(db(BOB)).collection('members').doc(ALICE).update({ hasPrivateAccounts: false }));
  });
});

describe('the app\'s account writes', () => {
  const newAccount = (uid, overrides) => {
    const doc = accountDoc({ balanceCheckedAt: null, ...overrides, ...createdBy(uid) });
    return { ...doc, visibilityAppliedTo: doc.visibleTo };
  };

  it('adding a private account, then its opening balance as an adjustment', async () => {
    const d = db(ALICE);
    const h = hh(d);
    const first = d.batch();
    first.set(h.collection('accounts').doc('wallet'), newAccount(ALICE, {
      name: 'Cash', kind: 'cash', currency: 'IQD', scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE],
    }));
    first.update(h.collection('members').doc(ALICE), { hasPrivateAccounts: true });
    await assertSucceeds(first.commit());

    const second = d.batch();
    second.set(h.collection('transactions').doc('open1'), {
      type: 'adjustment', adjustmentSign: 1, amountMinor: 250000, currency: 'IQD', accountId: 'wallet',
      baseAmountMinor: 250000, fx: null, categoryId: null, whoUid: ALICE, whoScope: 'member',
      occurredAt: new Date(), occurredOn: TODAY, title: '', source: 'manual', visibleTo: [ALICE],
      deletedAt: null, rev: 0, ...createdBy(ALICE),
    });
    second.update(h.collection('accounts').doc('wallet'), { balanceMinor: inc(250000), ...updatedBy(ALICE) });
    await assertSucceeds(second.commit());

    await assertFails(hh(db(BOB)).collection('accounts').doc('wallet').get());
    await assertFails(hh(db(BOB)).collection('transactions').doc('open1').get());
  });

  it('a USD opening balance in an IQD household stores the rate and today\'s rate document', async () => {
    const d = db(BOB);
    const h = hh(d);
    await assertSucceeds(h.collection('accounts').doc('visa').set(newAccount(BOB, {
      name: 'Joint Visa', kind: 'credit', currency: 'USD', scope: 'joint', ownerUid: null, visibleTo: [ALICE, BOB],
    })));
    const batch = d.batch();
    batch.set(h.collection('transactions').doc('open2'), {
      type: 'adjustment', adjustmentSign: -1, amountMinor: 61200, currency: 'USD', accountId: 'visa',
      baseAmountMinor: 1043460, fx: { pair: 'USD/IQD', pairRate: '1705', source: 'manual', asOf: TODAY },
      categoryId: null, whoUid: null, whoScope: 'joint', occurredAt: new Date(), occurredOn: TODAY,
      title: '', source: 'manual', visibleTo: [ALICE, BOB], deletedAt: null, rev: 0, ...createdBy(BOB),
    });
    batch.update(h.collection('accounts').doc('visa'), { balanceMinor: inc(-61200), ...updatedBy(BOB) });
    batch.set(h.collection('fxRates').doc(TODAY), { usdIqd: '1705', kind: 'market', enteredBy: BOB, enteredAt: serverTime() });
    await assertSucceeds(batch.commit());
  });

  it('the opening balance cannot ride in the account\'s own batch (why the app writes twice)', async () => {
    const d = db(ALICE);
    const h = hh(d);
    const batch = d.batch();
    batch.set(h.collection('accounts').doc('w2'), newAccount(ALICE, { scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE] }));
    batch.set(h.collection('transactions').doc('o2'), {
      type: 'adjustment', adjustmentSign: 1, amountMinor: 100, currency: 'IQD', accountId: 'w2',
      baseAmountMinor: 100, visibleTo: [ALICE], deletedAt: null, rev: 0, ...createdBy(ALICE),
    });
    await assertFails(batch.commit());
  });

  it('the owner shares an account, bumping its visibility rev; the partner then sees it', async () => {
    const d = db(ALICE);
    const h = hh(d);
    const batch = d.batch();
    batch.update(h.collection('accounts').doc('aPriv'), {
      sharedWithPartner: true, visibleTo: [ALICE, BOB], ...updatedBy(ALICE),
    });
    batch.update(h.collection('members').doc(ALICE), { hasPrivateAccounts: false });
    await assertSucceeds(batch.commit());

    await assertSucceeds(hh(db(BOB)).collection('accounts').doc('aPriv').get());
    // Its history follows only once the server's job rewrites visibleTo.
    await assertFails(hh(db(BOB)).collection('transactions').doc('tPriv').get());
  });

  it('the partner cannot share the owner\'s account, nor archive a private one', async () => {
    const acc = hh(db(BOB)).collection('accounts');
    await assertFails(acc.doc('aPriv').update({ sharedWithPartner: true, visibleTo: [ALICE, BOB], ...updatedBy(BOB) }));
    await assertFails(acc.doc('aPriv').update({ archived: true, ...updatedBy(BOB) }));
  });

  it('renaming and archiving keep the stamps', async () => {
    const acc = hh(db(BOB)).collection('accounts');
    await assertSucceeds(acc.doc('joint').update({ name: 'Family', kind: 'bank', ...updatedBy(BOB) }));
    await assertSucceeds(acc.doc('joint').update({ archived: true, ...updatedBy(BOB) }));
  });
});

describe('the visibility job\'s fields are the server\'s alone (security review, PR #33)', () => {
  const acc = (uid) => hh(db(uid)).collection('accounts');
  const sync = { runId: 'x', target: [ALICE], leaseUntil: new Date('9999-01-01'), done: 0, total: 0 };

  it('no member can set what the history was rewritten for, or a running rewrite', async () => {
    // The partner, on the owner's shared account: the attack in the review.
    await assertFails(acc(BOB).doc('aShared').update({ visibilityAppliedTo: [ALICE], ...updatedBy(BOB) }));
    await assertFails(acc(BOB).doc('aShared').update({ visibilitySync: sync, ...updatedBy(BOB) }));
    // Not the owner either, nor anyone on a joint account.
    await assertFails(acc(ALICE).doc('aShared').update({ visibilityAppliedTo: [ALICE], ...updatedBy(ALICE) }));
    await assertFails(acc(ALICE).doc('aPriv').update({ visibilitySync: null, visibilityAppliedTo: [ALICE, BOB], ...updatedBy(ALICE) }));
    await assertFails(acc(BOB).doc('joint').update({ visibilityAppliedTo: [BOB], ...updatedBy(BOB) }));
  });

  it('a new account may only start with its own visibleTo as applied, and no running rewrite', async () => {
    const base = { scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE], ...createdBy(ALICE) };
    await assertFails(acc(ALICE).doc('n1').set(accountDoc({ ...base, visibilityAppliedTo: [ALICE, BOB] })));
    await assertFails(acc(ALICE).doc('n2').set(accountDoc({ ...base, visibilityAppliedTo: [ALICE], visibilitySync: sync })));
    await assertSucceeds(acc(ALICE).doc('n3').set(accountDoc({ ...base, visibilityAppliedTo: [ALICE] })));
    await assertSucceeds(acc(ALICE).doc('n4').set(accountDoc(base)));
  });

  it('after the owner revokes sharing and the job runs, the partner reads nothing of it', async () => {
    // Shared history, as the job leaves it.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const h = hh(ctx.firestore());
      await h.collection('accounts').doc('aShared').update({ visibilityAppliedTo: [ALICE, BOB] });
      await h.collection('transactions').doc('tShared').set({
        type: 'expense', amountMinor: 500, currency: 'USD', accountId: 'aShared', baseAmountMinor: 500,
        visibleTo: [ALICE, BOB], deletedAt: null, rev: 0, title: 'Dinner',
      });
    });
    await assertSucceeds(hh(db(BOB)).collection('transactions').doc('tShared').get());

    // The owner turns sharing off; the phone writes only these fields.
    await assertSucceeds(acc(ALICE).doc('aShared').update({ sharedWithPartner: false, visibleTo: [ALICE], ...updatedBy(ALICE) }));
    await assertFails(acc(BOB).doc('aShared').get());

    // The server job rewrites the history (admin, no rules).
    await env.withSecurityRulesDisabled(async (ctx) => {
      const h = hh(ctx.firestore());
      await h.collection('transactions').doc('tShared').update({ visibleTo: [ALICE] });
      await h.collection('accounts').doc('aShared').update({ visibilityAppliedTo: [ALICE] });
    });
    const tx = hh(db(BOB)).collection('transactions');
    await assertFails(tx.doc('tShared').get());
    const list = await assertSucceeds(tx.where('visibleTo', 'array-contains', BOB).get());
    assert.ok(!list.docs.some((d) => d.id === 'tShared'));
  });
});
