// Shared fixtures for the rules tests. Runs only against the local emulator
// (`npm test` starts it through `firebase emulators:exec`).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

// Denied writes are the point of most tests; keep the SDK from logging each one.
firebase.firestore.setLogLevel('silent');

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// Must match the --project passed to emulators:exec (DELEGATION rule 4).
export const PROJECT_ID = 'xpense-dev';

export const ALICE = 'alice'; // owner of household h1
export const BOB = 'bob'; // partner in h1
export const EVE = 'eve'; // signed in, member of no household
export const CAROL = 'carol'; // member of another household h2

export const HID = 'h1';
export const TODAY = '2026-11-22';

export const serverTime = () => firebase.firestore.FieldValue.serverTimestamp();
const seedTime = new Date('2026-11-01T09:00:00Z');

export async function createEnv({ storage = false } = {}) {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is not set: run `npm test`, which starts the emulator.');
  }
  const config = {
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(join(root, 'firestore.rules'), 'utf8') },
  };
  if (storage) {
    config.storage = { rules: readFileSync(join(root, 'storage.rules'), 'utf8') };
  }
  return initializeTestEnvironment(config);
}

/** Audit stamps as the app writes them on create. */
export function createdBy(uid) {
  return { createdBy: uid, createdAt: serverTime(), updatedBy: uid, updatedAt: serverTime(), schemaVersion: 1 };
}

/** Audit stamps as the app writes them on update. */
export function updatedBy(uid) {
  return { updatedBy: uid, updatedAt: serverTime() };
}

function seedStamps(uid = ALICE) {
  return { createdBy: uid, createdAt: seedTime, updatedBy: uid, updatedAt: seedTime, schemaVersion: 1 };
}

export function accountDoc(overrides = {}) {
  return {
    name: 'Account', kind: 'cash', currency: 'IQD', scope: 'joint', ownerUid: null,
    sharedWithPartner: false, visibleTo: [ALICE, BOB], balanceMinor: 0, archived: false, order: 0,
    ...overrides,
  };
}

export function txnDoc(overrides = {}) {
  return {
    type: 'expense', amountMinor: 10000, currency: 'IQD', accountId: 'joint',
    baseAmountMinor: 10000, categoryId: 'groceries', whoUid: ALICE, whoScope: 'member',
    occurredAt: seedTime, occurredOn: TODAY, title: 'Lunch', source: 'manual',
    visibleTo: [ALICE, BOB], deletedAt: null, rev: 0,
    ...overrides,
  };
}

/** Collections that share the visibleTo pattern, with a minimal body each. */
export const VISIBLE_COLLECTIONS = {
  loans: { direction: 'given', kind: 'personal', personId: 'p1', principalMinor: 5000, currency: 'IQD', outstandingMinor: 5000, status: 'open' },
  goals: { name: 'Trip', targetMinor: 100000, currency: 'USD', accountId: 'savings', archived: false },
  budgets: { categoryId: 'groceries', period: 'monthly', limitMinor: 500000, alertAt: [0.8, 1.0] },
  recurring: { cadence: { unit: 'month', interval: 1 }, nextDueOn: TODAY, mode: 'remind', status: 'active' },
  rules: { kind: 'merchant', pattern: 'carrefour', sets: { categoryId: 'groceries' }, hits: 1 },
  people: { name: 'Karwan', aliases: [] },
};

/**
 * Seeds household h1 (alice + bob) and h2 (carol), with a private, a shared
 * and a joint account for alice, a private account for bob, and one private
 * and one joint document in every visibility-scoped collection.
 */
export async function seed(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const h = db.collection('households').doc(HID);
    const batch = db.batch();

    batch.set(db.doc(`users/${ALICE}`), { displayName: 'Alice', locale: 'en', householdId: HID });
    batch.set(db.doc(`users/${ALICE}/devices/d1`), { platform: 'ios', appVersion: '0.1.0' });
    batch.set(h, {
      name: 'Home', baseCurrency: 'IQD', timeZone: 'Asia/Baghdad', memberIds: [ALICE, BOB],
      rateKind: 'market', cloudInsights: true, weekStart: 'sat', moneySchema: 1, ...seedStamps(),
    });
    batch.set(db.doc('households/h2'), { name: 'Other', baseCurrency: 'USD', memberIds: [CAROL], moneySchema: 1 });
    batch.set(h.collection('members').doc(ALICE), { displayName: 'Alice', initial: 'A', role: 'owner', privacyMode: 'smart' });
    batch.set(h.collection('members').doc(BOB), { displayName: 'Bob', initial: 'B', role: 'partner', privacyMode: 'smart' });

    batch.set(h.collection('accounts').doc('aPriv'), accountDoc({ name: 'Alice cash', scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE], ...seedStamps() }));
    batch.set(h.collection('accounts').doc('aShared'), accountDoc({ name: 'Alice USD', currency: 'USD', scope: 'personal', ownerUid: ALICE, sharedWithPartner: true, ...seedStamps() }));
    batch.set(h.collection('accounts').doc('joint'), accountDoc({ name: 'Joint', ...seedStamps() }));
    batch.set(h.collection('accounts').doc('bPriv'), accountDoc({ name: 'Bob cash', scope: 'personal', ownerUid: BOB, visibleTo: [BOB], ...seedStamps(BOB) }));

    batch.set(h.collection('transactions').doc('tPriv'), txnDoc({ accountId: 'aPriv', visibleTo: [ALICE], title: 'Secret gift', ...seedStamps() }));
    batch.set(h.collection('transactions').doc('tJoint'), txnDoc({ rev: 3, ...seedStamps() }));
    batch.set(h.collection('transactions').doc('tPriv').collection('revisions').doc('1'), { rev: 1, before: { title: 'Gift' }, changedBy: ALICE, changedAt: seedTime, reason: 'edit' });
    batch.set(h.collection('transactions').doc('tJoint').collection('revisions').doc('1'), { rev: 1, before: { title: 'Lunch?' }, changedBy: BOB, changedAt: seedTime, reason: 'edit' });

    for (const [coll, body] of Object.entries(VISIBLE_COLLECTIONS)) {
      batch.set(h.collection(coll).doc('private'), { ...body, scope: 'personal', ownerUid: ALICE, visibleTo: [ALICE], ...seedStamps() });
      batch.set(h.collection(coll).doc('shared'), { ...body, scope: 'joint', ownerUid: null, visibleTo: [ALICE, BOB], ...seedStamps() });
    }

    batch.set(h.collection('categories').doc('groceries'), { slug: 'groceries', names: { en: 'Groceries' }, kind: 'expense', colorKey: 'cat1', iconKey: 'cart', order: 0, system: true, archived: false, ...seedStamps() });
    batch.set(h.collection('fxRates').doc('2026-11-21'), { usdIqd: '1520', kind: 'market', enteredBy: BOB, enteredAt: seedTime });
    batch.set(h.collection('notifications').doc('nAlice'), { type: 'budget_warning', titleKey: 't', bodyKey: 'b', params: {}, targetUids: [ALICE], readBy: [], dedupeKey: 'k1', createdAt: seedTime });
    batch.set(h.collection('notifications').doc('nBoth'), { type: 'monthly_report', titleKey: 't', bodyKey: 'b', params: {}, targetUids: [ALICE, BOB], readBy: [], dedupeKey: 'k2', createdAt: seedTime });
    batch.set(h.collection('usage').doc(TODAY), { agentTurns: 3 });

    batch.set(db.doc('invites/abc123'), { hid: HID, createdBy: ALICE, expiresAt: seedTime });
    batch.set(db.doc('config/runtime'), { model: 'x' });
    batch.set(db.doc('agentSessions/s1'), { state: {} });
    batch.set(db.doc('agentSessions/s1/messages/m1'), { text: 'hi' });
    batch.set(db.doc('agentSessions-pointers/p1'), { session: 's1' });
    batch.set(db.doc('agentSessions-shards/x1'), { data: '' });
    await batch.commit();
  });
}

export function hh(db) {
  return db.collection('households').doc(HID);
}
