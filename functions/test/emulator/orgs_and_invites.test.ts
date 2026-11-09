// Runs against the Firestore emulator: npm run test:emulator
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  acceptInviteImpl,
  createInviteImpl,
  listMyInvitesImpl,
  resendInviteImpl,
  revokeInviteImpl,
} from '../../src/invites/invites.ts';
import { createOrganizationImpl, MAX_OWNED_ORGS } from '../../src/orgs/create_organization.ts';

let app: App;
let db: Firestore;

const owner = { uid: 'owner1', email: 'owner@example.com' };
const anna = { uid: 'anna1', email: 'anna@example.com' };
const mallory = { uid: 'mallory1', email: 'mallory@example.com' };

function rejectsWith(reason: string) {
  return (e: unknown) => {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal((e.details as { reason?: string })?.reason, reason);
    return true;
  };
}

async function profile(uid: string, email: string, first = 'Test') {
  await db.doc(`users/${uid}`).set({ firstName: first, lastName: 'User', email });
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run with the Firestore emulator');
  app = initializeApp({ projectId: 'demo-standwise' }, 'orgs-test');
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  for (const c of ['orgs', 'users', 'mail']) {
    await db.recursiveDelete(db.collection(c));
  }
  await profile(owner.uid, owner.email, 'Olga');
  await profile(anna.uid, anna.email, 'Anna');
  await profile(mallory.uid, mallory.email, 'Mal');
});

async function newOrg(name = 'ACME') {
  const { orgId } = await createOrganizationImpl(db, owner, {
    name,
    currency: 'PLN',
    timezone: 'Europe/Warsaw',
  });
  return orgId;
}

describe('createOrganization', () => {
  it('creates a trial org with the caller as owner', async () => {
    const orgId = await newOrg();
    const org = (await db.doc(`orgs/${orgId}`).get()).data()!;
    assert.equal(org.status, 'trial');
    assert.equal(org.ownerUid, owner.uid);
    assert.equal(org.memberCount, 1);
    assert.equal(org.settings.currency, 'PLN');
    assert.ok((org.trialEndsAt as Timestamp).toMillis() > Date.now() + 29 * 86400000);

    const m = (await db.doc(`orgs/${orgId}/members/${owner.uid}`).get()).data()!;
    assert.deepEqual(
      { uid: m.uid, role: m.role, status: m.status, firstName: m.firstName },
      { uid: owner.uid, role: 'owner', status: 'active', firstName: 'Olga' },
    );
    assert.equal((await db.doc(`users/${owner.uid}`).get()).get('lastOrgId'), orgId);
    const audit = await db.collection(`orgs/${orgId}/auditLog`).get();
    assert.equal(audit.docs[0]!.get('action'), 'org.create');
  });

  it('requires a profile', async () => {
    await assert.rejects(
      createOrganizationImpl(db, { uid: 'nobody', email: 'n@example.com' }, {
        name: 'X',
        currency: 'EUR',
        timezone: 'Europe/Warsaw',
      }),
      rejectsWith('profile-required'),
    );
  });

  it('limits how many organizations one person owns', async () => {
    for (let i = 0; i < MAX_OWNED_ORGS; i++) await newOrg();
    await assert.rejects(newOrg(), rejectsWith('org-limit'));
  });
});

describe('invites', () => {
  it('invite → accept creates the membership with the invited role', async () => {
    const orgId = await newOrg();
    const { inviteId, code } = await createInviteImpl(db, owner, {
      orgId,
      email: anna.email,
      role: 'admin',
    });
    assert.match(code, /^[A-Z0-9]{4}-[A-Z0-9]{4}$/);

    const invite = (await db.doc(`orgs/${orgId}/invites/${inviteId}`).get()).data()!;
    assert.equal(invite.status, 'pending');
    assert.ok(!JSON.stringify(invite).includes(code), 'code must not be stored');
    const mail = await db.collection('mail').get();
    assert.equal(mail.size, 1);
    assert.deepEqual(mail.docs[0]!.get('to'), [anna.email]);

    const typed = code.toLowerCase().replace('-', ' ');
    assert.deepEqual(await acceptInviteImpl(db, anna, { code: typed }), { orgId });
    const m = (await db.doc(`orgs/${orgId}/members/${anna.uid}`).get()).data()!;
    assert.equal(m.role, 'admin');
    assert.equal(m.firstName, 'Anna');
    assert.equal((await db.doc(`orgs/${orgId}`).get()).get('memberCount'), 2);
    assert.equal((await db.doc(`orgs/${orgId}/invites/${inviteId}`).get()).get('status'), 'accepted');
    assert.equal((await db.doc(`users/${anna.uid}`).get()).get('lastOrgId'), orgId);

    // Accepting again is harmless and doesn't double-count.
    assert.deepEqual(await acceptInviteImpl(db, anna, { code }), { orgId });
    assert.equal((await db.doc(`orgs/${orgId}`).get()).get('memberCount'), 2);
  });

  it('only the invited email can accept', async () => {
    const orgId = await newOrg();
    const { code } = await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });
    await assert.rejects(acceptInviteImpl(db, mallory, { code }), rejectsWith('invite-email-mismatch'));
    assert.equal((await db.doc(`orgs/${orgId}/members/${mallory.uid}`).get()).exists, false);
  });

  it('lists my pending invites and joins one without the code', async () => {
    const orgId = await newOrg();
    const { inviteId } = await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });

    const { invites: mine } = await listMyInvitesImpl(db, anna);
    assert.equal(mine.length, 1);
    assert.equal(mine[0]!.orgId, orgId);
    assert.equal(mine[0]!.inviteId, inviteId);
    assert.equal(mine[0]!.role, 'employee');
    assert.equal(mine[0]!.inviterName, 'Olga User');
    assert.deepEqual(await listMyInvitesImpl(db, mallory), { invites: [] });

    // Someone else can't use the invite id either.
    await assert.rejects(acceptInviteImpl(db, mallory, { orgId, inviteId }), rejectsWith('invite-email-mismatch'));
    assert.deepEqual(await acceptInviteImpl(db, anna, { orgId, inviteId }), { orgId });
    assert.equal((await db.doc(`orgs/${orgId}/members/${anna.uid}`).get()).get('role'), 'employee');
    assert.deepEqual(await listMyInvitesImpl(db, anna), { invites: [] });
  });

  it('hides expired and revoked invites from the list', async () => {
    const orgId = await newOrg();
    const a = await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });
    await revokeInviteImpl(db, owner, { orgId, inviteId: a.inviteId });
    const org2 = await newOrg('Second');
    const b = await createInviteImpl(db, owner, { orgId: org2, email: anna.email, role: 'employee' });
    await db.doc(`orgs/${org2}/invites/${b.inviteId}`).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    assert.deepEqual(await listMyInvitesImpl(db, anna), { invites: [] });
    await assert.rejects(
      acceptInviteImpl(db, anna, { orgId: org2, inviteId: b.inviteId }),
      rejectsWith('invite-expired'),
    );
    await assert.rejects(
      acceptInviteImpl(db, anna, { orgId, inviteId: 'nope' }),
      rejectsWith('invite-not-found'),
    );
  });

  it('rejects unknown, expired, revoked and replaced codes', async () => {
    const orgId = await newOrg();
    await assert.rejects(acceptInviteImpl(db, anna, { code: 'ABCD-EFGH' }), rejectsWith('invite-not-found'));
    await assert.rejects(acceptInviteImpl(db, anna, { code: 'nonsense' }), rejectsWith('invite-not-found'));

    const first = await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });
    const resent = await resendInviteImpl(db, owner, { orgId, inviteId: first.inviteId });
    assert.notEqual(resent.code, first.code);
    await assert.rejects(acceptInviteImpl(db, anna, { code: first.code }), rejectsWith('invite-not-found'));

    await db.doc(`orgs/${orgId}/invites/${first.inviteId}`).update({
      expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    });
    await assert.rejects(acceptInviteImpl(db, anna, { code: resent.code }), rejectsWith('invite-expired'));

    const again = await resendInviteImpl(db, owner, { orgId, inviteId: first.inviteId });
    await revokeInviteImpl(db, owner, { orgId, inviteId: first.inviteId });
    await assert.rejects(acceptInviteImpl(db, anna, { code: again.code }), rejectsWith('invite-used'));
  });

  it('refuses duplicate invites and existing members', async () => {
    const orgId = await newOrg();
    await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });
    await assert.rejects(
      createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' }),
      rejectsWith('invite-pending'),
    );
    await assert.rejects(
      createInviteImpl(db, owner, { orgId, email: owner.email, role: 'employee' }),
      rejectsWith('already-member'),
    );
  });

  it('only active admins of a writable org can invite', async () => {
    const orgId = await newOrg();
    const { code } = await createInviteImpl(db, owner, { orgId, email: anna.email, role: 'employee' });
    await acceptInviteImpl(db, anna, { code });

    // Employees can't, outsiders can't.
    await assert.rejects(
      createInviteImpl(db, anna, { orgId, email: 'x@example.com', role: 'employee' }),
      rejectsWith('not-admin'),
    );
    await assert.rejects(
      createInviteImpl(db, mallory, { orgId, email: 'x@example.com', role: 'employee' }),
      rejectsWith('not-admin'),
    );
    // Suspended orgs are read-only.
    await db.doc(`orgs/${orgId}`).update({ status: 'suspended' });
    await assert.rejects(
      createInviteImpl(db, owner, { orgId, email: 'x@example.com', role: 'employee' }),
      rejectsWith('org-read-only'),
    );
  });
});
