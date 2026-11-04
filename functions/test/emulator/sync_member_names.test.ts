// Runs against the Firestore emulator: npm run test:emulator
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import { syncMemberNames } from '../../src/profile/sync_member_names.ts';

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run with the Firestore emulator');
  app = initializeApp({ projectId: 'demo-standwise' }, 'sync-test');
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

describe('syncMemberNames', () => {
  it('updates every membership of the user and nobody else', async () => {
    const member = (uid: string) => ({
      uid,
      role: 'employee',
      status: 'active',
      firstName: 'Old',
      lastName: 'Name',
      email: `${uid}@example.com`,
    });
    await db.doc('orgs/a/members/u1').set(member('u1'));
    await db.doc('orgs/b/members/u1').set(member('u1'));
    await db.doc('orgs/a/members/u2').set(member('u2'));

    const profile = { firstName: 'Łukasz', lastName: "O'Neil", email: 'u1@example.com' };
    assert.equal(await syncMemberNames(db, 'u1', profile), 2);

    for (const path of ['orgs/a/members/u1', 'orgs/b/members/u1']) {
      const m = (await db.doc(path).get()).data()!;
      assert.equal(m.firstName, 'Łukasz');
      assert.equal(m.lastName, "O'Neil");
      assert.equal(m.role, 'employee');
    }
    assert.equal((await db.doc('orgs/a/members/u2').get()).data()!.firstName, 'Old');

    // Running again changes nothing (triggers run at least once).
    assert.equal(await syncMemberNames(db, 'u1', profile), 0);
  });

  it('ignores incomplete profiles', async () => {
    assert.equal(await syncMemberNames(db, 'u1', { firstName: 'Only' }), 0);
  });
});
