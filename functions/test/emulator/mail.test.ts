// Runs against the Firestore emulator: npm run test:emulator
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import { inviteEmail } from '../../src/invites/email.ts';
import { deliverMail, MAIL_FROM, type OutgoingMail } from '../../src/mail/send_mail.ts';

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run with the Firestore emulator');
  app = initializeApp({ projectId: 'demo-standwise' }, 'mail-test');
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await db.recursiveDelete(db.collection('mail'));
});

async function queued(doc: object) {
  const ref = await db.collection('mail').add(doc);
  return { ref, data: (await ref.get()).data()! };
}

describe('sendMail', () => {
  it('sends an invite from the Standwise address and drops the body', async () => {
    const sent: OutgoingMail[] = [];
    const { ref, data } = await queued(
      inviteEmail({ to: 'anna@example.com', orgName: 'ACME', inviterName: 'Olga', code: 'ABCD-EFGH' }),
    );
    await deliverMail(ref, data, async (m) => {
      sent.push(m);
    });
    assert.equal(sent.length, 1);
    assert.equal(sent[0]!.from, MAIL_FROM);
    assert.deepEqual(sent[0]!.to, ['anna@example.com']);
    assert.match(sent[0]!.text, /ABCD-EFGH/);
    assert.ok(sent[0]!.html);

    const after = (await ref.get()).data()!;
    assert.equal(after.delivery.state, 'SUCCESS');
    assert.equal(after.message, undefined, 'the code must not stay stored');

    // A retried event doesn't send twice.
    await deliverMail(ref, after, async (m) => {
      sent.push(m);
    });
    assert.equal(sent.length, 1);
  });

  it('records SMTP failures and malformed documents', async () => {
    const a = await queued(inviteEmail({ to: 'a@example.com', orgName: 'X', inviterName: 'Y', code: 'C' }));
    await deliverMail(a.ref, a.data, async () => {
      throw new Error('535 auth failed');
    });
    const failed = (await a.ref.get()).data()!;
    assert.equal(failed.delivery.state, 'ERROR');
    assert.equal(failed.delivery.error, '535 auth failed');
    assert.ok(failed.message, 'kept for a later retry');

    const b = await queued({ to: ['nobody'], message: { subject: 'x' } });
    await deliverMail(b.ref, b.data, async () => assert.fail('must not send'));
    assert.equal((await b.ref.get()).get('delivery.error'), 'malformed');
  });
});
