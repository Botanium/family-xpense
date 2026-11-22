// Every bullet under "Rules tests must cover" in docs/DATA_MODEL.md section 5.
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  ALICE, BOB, EVE, CAROL, HID, VISIBLE_COLLECTIONS,
  accountDoc, createEnv, createdBy, hh, seed, txnDoc, updatedBy,
} from './setup.js';

let env;
const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(env); });

describe('a non-member reads nothing', () => {
  for (const [who, uid] of [['signed-in non-member', EVE], ['member of another household', CAROL], ['signed-out caller', null]]) {
    it(`${who} cannot read the household or anything in it`, async () => {
      const h = hh(db(uid));
      await assertFails(h.get());
      await assertFails(h.collection('members').get());
      await assertFails(h.collection('members').doc(ALICE).get());
      await assertFails(h.collection('accounts').doc('joint').get());
      await assertFails(h.collection('transactions').doc('tJoint').get());
      await assertFails(h.collection('transactions').doc('tJoint').collection('revisions').get());
      await assertFails(h.collection('categories').get());
      await assertFails(h.collection('fxRates').doc('2026-11-21').get());
      await assertFails(h.collection('notifications').doc('nBoth').get());
      for (const coll of Object.keys(VISIBLE_COLLECTIONS)) {
        await assertFails(h.collection(coll).doc('shared').get());
      }
      if (uid) {
        // Even a correctly filtered query is refused to a non-member.
        await assertFails(h.collection('accounts').where('visibleTo', 'array-contains', uid).get());
        await assertFails(h.collection('transactions').where('visibleTo', 'array-contains', uid).get());
      }
    });
  }

  it('households cannot be listed, even by a member', async () => {
    await assertFails(db(ALICE).collection('households').get());
    await assertFails(db(ALICE).collection('households').where('memberIds', 'array-contains', ALICE).get());
  });
});

describe('a partner cannot read a private account or its transactions', () => {
  it('bob cannot get alice\'s private account, its transaction or its revisions', async () => {
    const h = hh(db(BOB));
    await assertFails(h.collection('accounts').doc('aPriv').get());
    await assertFails(h.collection('transactions').doc('tPriv').get());
    await assertFails(h.collection('transactions').doc('tPriv').collection('revisions').get());
    await assertFails(h.collection('transactions').doc('tPriv').collection('revisions').doc('1').get());
  });

  it('bob\'s filtered queries never return alice\'s private data', async () => {
    const h = hh(db(BOB));
    const accounts = await assertSucceeds(h.collection('accounts').where('visibleTo', 'array-contains', BOB).get());
    assert.deepEqual(accounts.docs.map((d) => d.id).sort(), ['aShared', 'bPriv', 'joint']);
    const txns = await assertSucceeds(h.collection('transactions').where('visibleTo', 'array-contains', BOB).get());
    assert.deepEqual(txns.docs.map((d) => d.id), ['tJoint']);
    const byAccount = await assertSucceeds(h.collection('transactions')
      .where('visibleTo', 'array-contains', BOB).where('accountId', '==', 'aPriv').get());
    assert.equal(byAccount.size, 0);
  });

  it('alice can read her own private account and its transaction', async () => {
    const h = hh(db(ALICE));
    await assertSucceeds(h.collection('accounts').doc('aPriv').get());
    await assertSucceeds(h.collection('transactions').doc('tPriv').get());
    await assertSucceeds(h.collection('transactions').doc('tPriv').collection('revisions').get());
  });

  it('bob cannot read alice\'s private loan, goal, budget, recurring item, rule or person', async () => {
    for (const coll of Object.keys(VISIBLE_COLLECTIONS)) {
      await assertFails(hh(db(BOB)).collection(coll).doc('private').get());
      await assertSucceeds(hh(db(ALICE)).collection(coll).doc('private').get());
    }
  });
});

describe('list queries must carry the visibleTo filter', () => {
  const scoped = ['accounts', 'transactions', ...Object.keys(VISIBLE_COLLECTIONS)];

  for (const coll of scoped) {
    it(`${coll}: unfiltered list is refused, own filter is allowed`, async () => {
      for (const uid of [ALICE, BOB]) {
        await assertFails(hh(db(uid)).collection(coll).get());
        await assertFails(hh(db(uid)).collection(coll).limit(1).get());
        await assertSucceeds(hh(db(uid)).collection(coll).where('visibleTo', 'array-contains', uid).get());
      }
    });
  }

  it('a partner cannot filter on the other member\'s uid', async () => {
    await assertFails(hh(db(BOB)).collection('transactions').where('visibleTo', 'array-contains', ALICE).get());
    await assertFails(hh(db(BOB)).collection('accounts').where('visibleTo', 'array-contains', ALICE).get());
  });

  it('filters other than visibleTo do not prove the query', async () => {
    await assertFails(hh(db(BOB)).collection('transactions').where('accountId', '==', 'joint').get());
    await assertFails(hh(db(BOB)).collection('accounts').where('scope', '==', 'joint').get());
  });

  it('notifications need the targetUids filter', async () => {
    await assertFails(hh(db(BOB)).collection('notifications').get());
    const mine = await assertSucceeds(hh(db(BOB)).collection('notifications').where('targetUids', 'array-contains', BOB).get());
    assert.deepEqual(mine.docs.map((d) => d.id), ['nBoth']);
  });
});

describe('memberIds cannot be changed from the phone', () => {
  it('a member cannot add, remove or replace memberIds', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.update({ memberIds: [ALICE, BOB, EVE] }));
    await assertFails(h.update({ memberIds: [ALICE] }));
    await assertFails(hh(db(BOB)).update({ memberIds: [BOB] }));
  });

  it('a non-member cannot add themself', async () => {
    await assertFails(hh(db(EVE)).update({ memberIds: [ALICE, BOB, EVE] }));
    await assertFails(hh(db(EVE)).set({ name: 'Mine', baseCurrency: 'IQD', memberIds: [EVE] }));
  });

  it('a new household can only list its creator', async () => {
    const h = db(EVE).collection('households');
    await assertFails(h.doc('h3').set({ name: 'X', baseCurrency: 'IQD', memberIds: [EVE, ALICE] }));
    await assertFails(h.doc('h4').set({ name: 'X', baseCurrency: 'IQD', memberIds: [ALICE] }));
    await assertSucceeds(h.doc('h5').set({ name: 'X', baseCurrency: 'IQD', memberIds: [EVE], moneySchema: 1 }));
  });

  it('other server-owned household fields are locked too', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.update({ baseCurrency: 'USD' }));
    await assertFails(h.update({ moneySchema: 2 }));
    await assertFails(h.update({ cloudInsights: false }));
    await assertSucceeds(h.update({ name: 'Our home', rateKind: 'official', rateAskedOn: '2026-11-22' }));
  });
});

describe('visibleTo cannot name a non-member', () => {
  it('on create', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.collection('accounts').doc('x').set(accountDoc({ visibleTo: [ALICE, BOB, EVE], ...createdBy(ALICE) })));
    await assertFails(h.collection('accounts').doc('y').set(accountDoc({ scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE, CAROL], ...createdBy(ALICE) })));
    for (const [coll, body] of Object.entries(VISIBLE_COLLECTIONS)) {
      await assertFails(h.collection(coll).doc('x').set({ ...body, visibleTo: [ALICE, EVE], ...createdBy(ALICE) }));
    }
  });

  it('on update', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.collection('accounts').doc('joint').update({ visibleTo: [ALICE, BOB, EVE], ...updatedBy(ALICE) }));
    await assertFails(h.collection('transactions').doc('tJoint').update({ visibleTo: [ALICE, BOB, EVE], rev: 4, ...updatedBy(ALICE) }));
    await assertFails(h.collection('loans').doc('shared').update({ visibleTo: [ALICE, BOB, EVE], ...updatedBy(ALICE) }));
  });

  it('visibleTo cannot be empty or missing', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.collection('people').doc('x').set({ name: 'Nobody', visibleTo: [], ...createdBy(ALICE) }));
    await assertFails(h.collection('people').doc('y').set({ name: 'Nobody', ...createdBy(ALICE) }));
  });
});

describe('rev must advance by exactly 1', () => {
  const edit = (uid, fields) => hh(db(uid)).collection('transactions').doc('tJoint').update({ title: 'Dinner', ...updatedBy(uid), ...fields });

  it('rev + 1 is accepted', async () => {
    await assertSucceeds(edit(BOB, { rev: 4 }));
  });

  it('the same rev, a skipped rev, a lower rev or no rev change is refused', async () => {
    await assertFails(edit(BOB, { rev: 3 }));
    await assertFails(edit(BOB, { rev: 5 }));
    await assertFails(edit(BOB, { rev: 2 }));
    await assertFails(edit(BOB, {}));
    await assertFails(edit(BOB, { rev: '4' }));
  });

  it('the losing write of two concurrent edits is refused', async () => {
    await assertSucceeds(edit(ALICE, { rev: 4 }));
    await assertFails(edit(BOB, { rev: 4 }));
    await assertSucceeds(edit(BOB, { rev: 5 }));
  });

  it('a new transaction starts at rev 0', async () => {
    const t = hh(db(ALICE)).collection('transactions');
    await assertFails(t.doc('n1').set(txnDoc({ rev: 7, ...createdBy(ALICE) })));
    await assertSucceeds(t.doc('n2').set(txnDoc({ rev: 0, ...createdBy(ALICE) })));
  });
});

describe('hard deletes are refused', () => {
  it('transactions are soft-deleted, never removed', async () => {
    const t = hh(db(ALICE)).collection('transactions').doc('tJoint');
    await assertFails(t.delete());
    await assertSucceeds(t.update({ deletedAt: new Date(), rev: 4, ...updatedBy(ALICE) }));
    await assertFails(t.delete());
    // Restore is an edit too.
    await assertSucceeds(t.update({ deletedAt: null, rev: 5, ...updatedBy(ALICE) }));
  });

  it('accounts, loans, goals, people, categories, members, revisions, fxRates and the household cannot be deleted', async () => {
    const h = hh(db(ALICE));
    await assertFails(h.collection('accounts').doc('aPriv').delete());
    await assertFails(h.collection('loans').doc('private').delete());
    await assertFails(h.collection('goals').doc('private').delete());
    await assertFails(h.collection('people').doc('private').delete());
    await assertFails(h.collection('categories').doc('groceries').delete());
    await assertFails(h.collection('members').doc(ALICE).delete());
    await assertFails(h.collection('transactions').doc('tPriv').collection('revisions').doc('1').delete());
    await assertFails(h.collection('fxRates').doc('2026-11-21').delete());
    await assertFails(h.delete());
  });

  it('rules, budgets and recurring items may be deleted by a member who can see them (design exception)', async () => {
    for (const coll of ['rules', 'budgets', 'recurring']) {
      await assertFails(hh(db(BOB)).collection(coll).doc('private').delete());
      await assertSucceeds(hh(db(BOB)).collection(coll).doc('shared').delete());
    }
  });
});

describe('server-only collections refuse every phone read and write', () => {
  const paths = [
    'invites/abc123',
    'config/runtime',
    'config/migrations/v2/state',
    'agentSessions/s1',
    'agentSessions/s1/messages/m1',
    'agentSessions-pointers/p1',
    'agentSessions-shards/x1',
    `households/${HID}/usage/2026-11-22`,
  ];

  for (const path of paths) {
    it(path, async () => {
      for (const uid of [ALICE, BOB, EVE]) {
        const d = db(uid).doc(path);
        await assertFails(d.get());
        await assertFails(d.set({ x: 1 }));
        await assertFails(d.update({ x: 2 }));
        await assertFails(d.delete());
        await assertFails(d.parent.get());
      }
    });
  }

  it('session collections with a household or member prefix are denied by default', async () => {
    for (const path of [`agentSessions_${HID}/s1`, `agentSessions-${HID}-${ALICE}/s1`]) {
      await assertFails(db(ALICE).doc(path).get());
      await assertFails(db(ALICE).doc(path).set({ x: 1 }));
    }
  });

  it('notifications are created and deleted by the server only', async () => {
    const n = hh(db(ALICE)).collection('notifications');
    await assertFails(n.doc('mine').set({ type: 'partner_activity', targetUids: [ALICE], readBy: [] }));
    await assertFails(n.doc('nAlice').delete());
  });

  it('member documents are created by the server (join endpoint)', async () => {
    await assertFails(hh(db(EVE)).collection('members').doc(EVE).set({ displayName: 'Eve', role: 'partner' }));
    await assertFails(hh(db(ALICE)).collection('members').doc(EVE).set({ displayName: 'Eve', role: 'partner' }));
  });
});
