// Runs against the Firestore emulator: npm run test:emulator
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { deleteAccountImpl } from '../../src/account/delete_account.ts';
import {
  leaveOrganizationImpl,
  removeMemberImpl,
  setMemberRoleImpl,
  setMemberStatusImpl,
  transferOwnershipImpl,
} from '../../src/members/members.ts';
import { createOrganizationImpl } from '../../src/orgs/create_organization.ts';
import { deleteOrganizationImpl } from '../../src/orgs/delete_organization.ts';
import { recomputeSummary } from '../../src/summaries/recompute.ts';
import { purgeDeletedEntriesImpl } from '../../src/summaries/triggers.ts';

let app: App;
let db: Firestore;

const owner = { uid: 'owner1', email: 'owner@example.com' };
const admin = { uid: 'admin1', email: 'admin@example.com' };
const anna = { uid: 'anna1', email: 'anna@example.com' };

function rejectsWith(reason: string) {
  return (e: unknown) => {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal((e.details as { reason?: string })?.reason, reason);
    return true;
  };
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run with the Firestore emulator');
  app = initializeApp({ projectId: 'demo-standwise' }, 'members-test');
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

let orgId: string;

async function addMember(uid: string, email: string, role: 'admin' | 'employee') {
  await db.doc(`orgs/${orgId}/members/${uid}`).set({
    uid,
    role,
    status: 'active',
    firstName: 'Test',
    lastName: 'User',
    email,
    joinedAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`orgs/${orgId}`).update({ memberCount: FieldValue.increment(1) });
}

beforeEach(async () => {
  for (const c of ['orgs', 'users', 'mail']) {
    await db.recursiveDelete(db.collection(c));
  }
  for (const u of [owner, admin, anna]) {
    await db.doc(`users/${u.uid}`).set({ firstName: 'Test', lastName: 'User', email: u.email });
  }
  ({ orgId } = await createOrganizationImpl(db, owner, {
    name: 'ACME',
    currency: 'PLN',
    timezone: 'Europe/Warsaw',
  }));
  await addMember(admin.uid, admin.email, 'admin');
  await addMember(anna.uid, anna.email, 'employee');
});

const member = async (uid: string) => (await db.doc(`orgs/${orgId}/members/${uid}`).get()).data();

describe('member management', () => {
  it('admins change roles and status of others, with an audit entry', async () => {
    await setMemberRoleImpl(db, admin, { orgId, uid: anna.uid, role: 'admin' });
    assert.equal((await member(anna.uid))?.role, 'admin');
    await setMemberStatusImpl(db, admin, { orgId, uid: anna.uid, status: 'disabled' });
    assert.equal((await member(anna.uid))?.status, 'disabled');
    const actions = (await db.collection(`orgs/${orgId}/auditLog`).get()).docs.map((d) => d.get('action'));
    assert.ok(actions.includes('member.role'));
    assert.ok(actions.includes('member.disable'));
  });

  it('protects the owner and the caller', async () => {
    await assert.rejects(
      setMemberRoleImpl(db, admin, { orgId, uid: owner.uid, role: 'employee' }),
      rejectsWith('owner-protected'),
    );
    await assert.rejects(
      setMemberStatusImpl(db, admin, { orgId, uid: admin.uid, status: 'disabled' }),
      rejectsWith('self-change'),
    );
    await assert.rejects(
      setMemberRoleImpl(db, anna, { orgId, uid: admin.uid, role: 'employee' }),
      rejectsWith('not-admin'),
    );
  });

  it('removing a member deletes membership, rates and timer but keeps entries', async () => {
    await db.doc(`orgs/${orgId}/members/${anna.uid}/rates/p1`).set({ workRateMinor: 1 });
    await db.doc(`orgs/${orgId}/timers/${anna.uid}`).set({ type: 'work' });
    await db.doc(`orgs/${orgId}/entries/e1`).set({ uid: anna.uid });
    await db.doc(`users/${anna.uid}`).update({ lastOrgId: orgId });

    await removeMemberImpl(db, owner, { orgId, uid: anna.uid });

    assert.equal(await member(anna.uid), undefined);
    assert.equal((await db.collection(`orgs/${orgId}/members/${anna.uid}/rates`).get()).size, 0);
    assert.equal((await db.doc(`orgs/${orgId}/timers/${anna.uid}`).get()).exists, false);
    assert.equal((await db.doc(`orgs/${orgId}/entries/e1`).get()).exists, true);
    assert.equal((await db.doc(`orgs/${orgId}`).get()).get('memberCount'), 2);
    assert.equal((await db.doc(`users/${anna.uid}`).get()).get('lastOrgId'), undefined);
  });

  it('the owner transfers ownership and becomes admin', async () => {
    await assert.rejects(
      transferOwnershipImpl(db, admin, { orgId, uid: anna.uid }),
      rejectsWith('not-owner'),
    );
    await transferOwnershipImpl(db, owner, { orgId, uid: anna.uid });
    assert.equal((await member(anna.uid))?.role, 'owner');
    assert.equal((await member(owner.uid))?.role, 'admin');
    assert.equal((await db.doc(`orgs/${orgId}`).get()).get('ownerUid'), anna.uid);
  });

  it('members leave; the owner cannot', async () => {
    await leaveOrganizationImpl(db, anna, { orgId });
    assert.equal(await member(anna.uid), undefined);
    await assert.rejects(leaveOrganizationImpl(db, owner, { orgId }), rejectsWith('owner-must-transfer'));
  });
});

describe('deleting', () => {
  it('only the owner deletes the organization, after typing its name', async () => {
    await db.doc(`orgs/${orgId}/entries/e1`).set({ uid: anna.uid });
    await assert.rejects(
      deleteOrganizationImpl(db, admin, { orgId, confirmName: 'ACME' }),
      rejectsWith('not-owner'),
    );
    await assert.rejects(
      deleteOrganizationImpl(db, owner, { orgId, confirmName: 'Acme Inc' }),
      rejectsWith('name-mismatch'),
    );
    await deleteOrganizationImpl(db, owner, { orgId, confirmName: ' ACME ' });
    assert.equal((await db.doc(`orgs/${orgId}`).get()).exists, false);
    assert.equal((await db.collection(`orgs/${orgId}/entries`).get()).size, 0);
    assert.equal((await db.collection(`orgs/${orgId}/members`).get()).size, 0);
  });

  it('deleting an account removes memberships and profile, keeps hours', async () => {
    await db.doc(`orgs/${orgId}/entries/e1`).set({ uid: anna.uid });
    const deleted: string[] = [];
    await deleteAccountImpl(db, anna, async (uid) => {
      deleted.push(uid);
    });
    assert.deepEqual(deleted, [anna.uid]);
    assert.equal(await member(anna.uid), undefined);
    assert.equal((await db.doc(`users/${anna.uid}`).get()).exists, false);
    assert.equal((await db.doc(`orgs/${orgId}/entries/e1`).get()).exists, true);
  });

  it('an owner must transfer or delete the organization first', async () => {
    await assert.rejects(
      deleteAccountImpl(db, owner, async () => {}),
      rejectsWith('owner-must-transfer'),
    );
    assert.equal((await db.doc(`users/${owner.uid}`).get()).exists, true);
  });
});

describe('summaries', () => {
  async function entry(id: string, startIso: string, minutes: number, extra: Record<string, unknown> = {}) {
    const start = new Date(startIso);
    await db.doc(`orgs/${orgId}/entries/${id}`).set({
      uid: anna.uid,
      type: 'work',
      rateMinor: 6000,
      start: Timestamp.fromDate(start),
      end: Timestamp.fromMillis(start.getTime() + minutes * 60000),
      durationMin: minutes,
      description: '',
      monthKey: '2026-11',
      deleted: false,
      ...extra,
    });
  }

  it('are recomputed from the month entries and removed when empty', async () => {
    await entry('a', '2026-11-02T08:00:00Z', 90, { projectId: 'p1' });
    await entry('b', '2026-11-02T23:30:00Z', 60, { type: 'standby', rateMinor: 1500 });
    await entry('c', '2026-11-05T08:00:00Z', 60, { deleted: true });

    assert.equal(await recomputeSummary(db, orgId, { uid: anna.uid, monthKey: '2026-11' }), 'written');
    const s = (await db.doc(`orgs/${orgId}/summaries/${anna.uid}_2026-11`).get()).data()!;
    assert.equal(s.uid, anna.uid);
    assert.deepEqual(Object.keys(s.days).sort(), ['02', '03']);
    assert.equal(s.days['02'].workMin, 90);
    assert.equal(s.days['03'].standbyMin, 60);

    await db.recursiveDelete(db.collection(`orgs/${orgId}/entries`));
    assert.equal(await recomputeSummary(db, orgId, { uid: anna.uid, monthKey: '2026-11' }), 'deleted');
    assert.equal((await db.doc(`orgs/${orgId}/summaries/${anna.uid}_2026-11`).get()).exists, false);
  });

  it('skip organizations that are being deleted', async () => {
    await db.doc(`orgs/${orgId}`).delete();
    assert.equal(await recomputeSummary(db, orgId, { uid: anna.uid, monthKey: '2026-11' }), 'skipped');
  });

  it('purge hard-deletes entries soft-deleted over 30 days ago', async () => {
    const old = Timestamp.fromMillis(Date.now() - 31 * 86400000);
    await entry('old', '2026-09-01T08:00:00Z', 60, { deleted: true, updatedAt: old });
    await entry('recent', '2026-11-01T08:00:00Z', 60, { deleted: true, updatedAt: Timestamp.now() });
    await entry('kept', '2026-09-01T08:00:00Z', 60, { updatedAt: old });
    assert.equal(await purgeDeletedEntriesImpl(db), 1);
    const left = (await db.collection(`orgs/${orgId}/entries`).get()).docs.map((d) => d.id).sort();
    assert.deepEqual(left, ['kept', 'recent']);
  });
});
