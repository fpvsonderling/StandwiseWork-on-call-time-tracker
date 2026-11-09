import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentReference,
  type Firestore,
} from 'firebase-admin/firestore';
import { z } from 'zod';

import { requireActiveAdmin } from '../lib/access.ts';
import type { Caller } from '../lib/auth.ts';
import { writeAudit } from '../lib/audit.ts';
import { callable } from '../lib/callable.ts';
import { fail } from '../lib/errors.ts';
import { fullName } from '../lib/names.ts';
import { requireProfile } from '../lib/profile.ts';
import { generateInviteCode, hashInviteCode, normalizeInviteCode } from './code.ts';
import { inviteEmail } from './email.ts';

export const INVITE_DAYS = 7;

const orgId = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);
const inviteId = orgId;

export const createInviteInput = z.object({
  orgId,
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  role: z.enum(['employee', 'admin']),
});
export const inviteRefInput = z.object({ orgId, inviteId });
export const acceptInviteInput = z.union([
  z.object({ code: z.string().max(32) }),
  inviteRefInput,
]);
export const listMyInvitesInput = z.object({}).optional();

export interface MyInvite {
  orgId: string;
  inviteId: string;
  orgName: string;
  inviterName: string;
  role: string;
  expiresAt: string;
}

function expiry(): Timestamp {
  return Timestamp.fromMillis(Date.now() + INVITE_DAYS * 24 * 60 * 60 * 1000);
}

async function queueEmail(
  db: Firestore,
  to: string,
  orgName: string,
  inviterUid: string,
  code: string,
): Promise<void> {
  const inviter = await requireProfile(db, inviterUid);
  await db.collection('mail').add({
    ...inviteEmail({
      to,
      orgName,
      inviterName: fullName(inviter.firstName, inviter.lastName),
      code,
    }),
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Admin invites an email address with a role (spec §5.6). Returns the code
 * so the admin can also share it directly; only its hash is stored.
 */
export async function createInviteImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof createInviteInput>,
): Promise<{ inviteId: string; code: string; expiresAt: string }> {
  const { org } = await requireActiveAdmin(db, input.orgId, caller.uid);
  const orgRef = db.doc(`orgs/${input.orgId}`);

  const existingMember = await orgRef
    .collection('members')
    .where('email', '==', input.email)
    .limit(1)
    .get();
  if (!existingMember.empty) {
    fail('already-exists', 'already-member', 'This person is already a member.');
  }
  const invitesForEmail = await orgRef.collection('invites').where('email', '==', input.email).get();
  const pending = invitesForEmail.docs.some(
    (d) => d.get('status') === 'pending' && (d.get('expiresAt') as Timestamp).toMillis() > Date.now(),
  );
  if (pending) {
    fail('already-exists', 'invite-pending', 'An invite for this email is pending; resend it instead.');
  }

  const code = generateInviteCode();
  const ref = orgRef.collection('invites').doc();
  const expiresAt = expiry();
  await ref.set({
    email: input.email,
    role: input.role,
    codeHash: hashInviteCode(normalizeInviteCode(code)!),
    expiresAt,
    status: 'pending',
    createdBy: caller.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await queueEmail(db, input.email, org.name, caller.uid, code);
  await writeAudit(db, input.orgId, {
    actorUid: caller.uid,
    action: 'invite.create',
    entity: 'invite',
    entityId: ref.id,
    details: { email: input.email, role: input.role },
  });
  return { inviteId: ref.id, code, expiresAt: expiresAt.toDate().toISOString() };
}

/** New code and a fresh 7-day expiry for a pending or expired invite. */
export async function resendInviteImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof inviteRefInput>,
): Promise<{ code: string; expiresAt: string }> {
  const { org } = await requireActiveAdmin(db, input.orgId, caller.uid);
  const ref = db.doc(`orgs/${input.orgId}/invites/${input.inviteId}`);
  const invite = (await ref.get()).data();
  if (!invite) fail('not-found', 'invite-not-found', 'Invite not found.');
  if (invite.status !== 'pending') fail('failed-precondition', 'invite-used', 'Invite is no longer pending.');

  const code = generateInviteCode();
  const expiresAt = expiry();
  await ref.update({
    codeHash: hashInviteCode(normalizeInviteCode(code)!),
    expiresAt,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await queueEmail(db, invite.email, org.name, caller.uid, code);
  await writeAudit(db, input.orgId, {
    actorUid: caller.uid,
    action: 'invite.resend',
    entity: 'invite',
    entityId: input.inviteId,
    details: { email: invite.email },
  });
  return { code, expiresAt: expiresAt.toDate().toISOString() };
}

export async function revokeInviteImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof inviteRefInput>,
): Promise<{ ok: true }> {
  await requireActiveAdmin(db, input.orgId, caller.uid);
  const ref = db.doc(`orgs/${input.orgId}/invites/${input.inviteId}`);
  const invite = (await ref.get()).data();
  if (!invite) fail('not-found', 'invite-not-found', 'Invite not found.');
  if (invite.status === 'pending') {
    await ref.update({ status: 'revoked', updatedAt: FieldValue.serverTimestamp() });
    await writeAudit(db, input.orgId, {
      actorUid: caller.uid,
      action: 'invite.revoke',
      entity: 'invite',
      entityId: input.inviteId,
      details: { email: invite.email },
    });
  }
  return { ok: true };
}

/**
 * The invited person joins with the code, or by picking the invite from
 * [listMyInvitesImpl] (spec §4.3). Either way the signed-in, verified email
 * must match the invited email. Idempotent: accepting twice
 * returns the same organization.
 */
export async function acceptInviteImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof acceptInviteInput>,
): Promise<{ orgId: string }> {
  const profile = await requireProfile(db, caller.uid);
  let inviteRef: DocumentReference;
  if ('code' in input) {
    const normalized = normalizeInviteCode(input.code);
    if (!normalized) fail('not-found', 'invite-not-found', 'Invite not found.');
    const found = await db
      .collectionGroup('invites')
      .where('codeHash', '==', hashInviteCode(normalized))
      .limit(1)
      .get();
    const ref = found.docs[0]?.ref;
    if (!ref) fail('not-found', 'invite-not-found', 'Invite not found.');
    inviteRef = ref;
  } else {
    // Joining from the in-app invitation list: the verified email match
    // below is the proof, so no code is needed.
    inviteRef = db.doc(`orgs/${input.orgId}/invites/${input.inviteId}`);
  }
  const orgRef = inviteRef.parent.parent!;
  const memberRef = orgRef.collection('members').doc(caller.uid);

  await db.runTransaction(async (tx) => {
    const [inviteSnap, memberSnap, orgSnap] = await Promise.all([
      tx.get(inviteRef),
      tx.get(memberRef),
      tx.get(orgRef),
    ]);
    const invite = inviteSnap.data();
    if (!invite || !orgSnap.exists) fail('not-found', 'invite-not-found', 'Invite not found.');
    if (invite.email !== caller.email) {
      fail('permission-denied', 'invite-email-mismatch', 'This invite is for a different email address.');
    }
    if (invite.status === 'accepted' && invite.acceptedBy === caller.uid && memberSnap.exists) {
      return; // Already joined: idempotent retry.
    }
    if (invite.status !== 'pending') fail('failed-precondition', 'invite-used', 'Invite is no longer valid.');
    if ((invite.expiresAt as Timestamp).toMillis() < Date.now()) {
      fail('deadline-exceeded', 'invite-expired', 'Invite has expired.');
    }
    if (!['trial', 'active'].includes(orgSnap.data()!.status)) {
      fail('failed-precondition', 'org-read-only', 'This organization is read-only.');
    }

    const now = FieldValue.serverTimestamp();
    if (!memberSnap.exists) {
      tx.set(memberRef, {
        uid: caller.uid,
        role: invite.role,
        status: 'active',
        firstName: profile.firstName,
        lastName: profile.lastName,
        email: profile.email,
        joinedAt: now,
        updatedAt: now,
      });
      tx.update(orgRef, { memberCount: FieldValue.increment(1), updatedAt: now });
    }
    tx.update(inviteRef, { status: 'accepted', acceptedBy: caller.uid, acceptedAt: now, updatedAt: now });
    tx.update(db.doc(`users/${caller.uid}`), { lastOrgId: orgRef.id, updatedAt: now });
  });

  await writeAudit(db, orgRef.id, {
    actorUid: caller.uid,
    action: 'invite.accept',
    entity: 'invite',
    entityId: inviteRef.id,
    details: { email: caller.email },
  });
  return { orgId: orgRef.id };
}

/**
 * Pending, unexpired invites for the caller's verified email, so the app can
 * offer "Join" without typing the code.
 */
export async function listMyInvitesImpl(
  db: Firestore,
  caller: Caller,
): Promise<{ invites: MyInvite[] }> {
  const snap = await db.collectionGroup('invites').where('email', '==', caller.email).get();
  const now = Date.now();
  const pending = snap.docs.filter(
    (d) => d.get('status') === 'pending' && (d.get('expiresAt') as Timestamp).toMillis() > now,
  );
  const result: MyInvite[] = [];
  for (const d of pending) {
    const orgRef = d.ref.parent.parent!;
    const [org, member, inviter] = await Promise.all([
      orgRef.get(),
      orgRef.collection('members').doc(caller.uid).get(),
      db.doc(`users/${d.get('createdBy')}`).get(),
    ]);
    if (!org.exists || member.exists) continue;
    if (!['trial', 'active'].includes(org.get('status'))) continue;
    result.push({
      orgId: orgRef.id,
      inviteId: d.id,
      orgName: org.get('name') ?? '',
      inviterName: fullName(inviter.get('firstName') ?? '', inviter.get('lastName') ?? ''),
      role: d.get('role'),
      expiresAt: (d.get('expiresAt') as Timestamp).toDate().toISOString(),
    });
  }
  return { invites: result.sort((a, b) => a.orgName.localeCompare(b.orgName)) };
}

export const createInvite = callable(createInviteInput, (caller, input) =>
  createInviteImpl(getFirestore(), caller, input),
);
export const resendInvite = callable(inviteRefInput, (caller, input) =>
  resendInviteImpl(getFirestore(), caller, input),
);
export const revokeInvite = callable(inviteRefInput, (caller, input) =>
  revokeInviteImpl(getFirestore(), caller, input),
);
export const acceptInvite = callable(acceptInviteInput, (caller, input) =>
  acceptInviteImpl(getFirestore(), caller, input),
);
export const listMyInvites = callable(listMyInvitesInput, (caller) =>
  listMyInvitesImpl(getFirestore(), caller),
);
