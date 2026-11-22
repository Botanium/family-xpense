// Receipt images: households/{hid}/receipts/{txnId}/{file}.
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ALICE, BOB, EVE, HID, createEnv, seed } from './setup.js';

let env;
const storage = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
const receipt = (uid, txnId, file = 'r1.jpg') => storage(uid).ref(`households/${HID}/receipts/${txnId}/${file}`);

const smallImage = new Uint8Array(1024).fill(7);
const jpeg = { contentType: 'image/jpeg' };

before(async () => { env = await createEnv({ storage: true }); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.storage().ref(`households/${HID}/receipts/tPriv/r0.jpg`).put(smallImage, jpeg);
    await ctx.storage().ref(`households/${HID}/receipts/tJoint/r0.jpg`).put(smallImage, jpeg);
  });
});

describe('storage: receipts', () => {
  it('a member who can see the transaction uploads, reads and deletes an image', async () => {
    await assertSucceeds(receipt(ALICE, 'tPriv').put(smallImage, jpeg));
    await assertSucceeds(receipt(ALICE, 'tPriv', 'r0.jpg').getMetadata());
    await assertSucceeds(receipt(BOB, 'tJoint', 'r0.jpg').getMetadata());
    await assertSucceeds(receipt(BOB, 'tJoint', 'r2.png').put(smallImage, { contentType: 'image/png' }));
    await assertSucceeds(receipt(BOB, 'tJoint', 'r0.jpg').delete());
  });

  it('the partner cannot read or write a private transaction\'s receipt', async () => {
    await assertFails(receipt(BOB, 'tPriv', 'r0.jpg').getMetadata());
    await assertFails(receipt(BOB, 'tPriv').put(smallImage, jpeg));
    await assertFails(receipt(BOB, 'tPriv', 'r0.jpg').delete());
  });

  it('non-members and signed-out callers are refused', async () => {
    await assertFails(receipt(EVE, 'tJoint', 'r0.jpg').getMetadata());
    await assertFails(receipt(EVE, 'tJoint').put(smallImage, jpeg));
    await assertFails(receipt(null, 'tJoint', 'r0.jpg').getMetadata());
  });

  it('only images up to 5 MB are accepted, for a transaction that exists', async () => {
    await assertFails(receipt(ALICE, 'tJoint', 'r.pdf').put(smallImage, { contentType: 'application/pdf' }));
    await assertFails(receipt(ALICE, 'tJoint', 'r.txt').put(smallImage, { contentType: 'text/plain' }));
    await assertSucceeds(receipt(ALICE, 'tJoint', 'max.jpg').put(new Uint8Array(5 * 1024 * 1024), jpeg));
    await assertFails(receipt(ALICE, 'tJoint', 'big.jpg').put(new Uint8Array(5 * 1024 * 1024 + 1), jpeg));
    await assertFails(receipt(ALICE, 'missing').put(smallImage, jpeg));
  });

  it('nothing outside the receipts path is writable', async () => {
    await assertFails(storage(ALICE).ref(`households/${HID}/other.jpg`).put(smallImage, jpeg));
    await assertFails(storage(ALICE).ref(`users/${ALICE}/avatar.jpg`).put(smallImage, jpeg));
  });
});
