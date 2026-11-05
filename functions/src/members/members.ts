import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { z } from 'zod';

import { requireActiveAdmin, requireMember, type Membership } from '../lib/access.ts';
import type { Caller } from '../lib/auth.ts';
import { writeAudit } from '../lib/audit.ts';
import { callable } from '../lib/callable.ts';
import { fail } from '../lib/errors.ts';
import { removeMembership } from './remove.ts';

const id = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);

export const setMemberRoleInput = z.object({ orgId: id, uid: id, role: z.enum(['admin', 'employee']) });
export const setMemberStatusInput = z.object({ orgId: id, uid: id, status: z.enum(['active', 'disabled']) });
export const memberRefInput = z.object({ orgId: id, uid: id });
export const orgRefInput = z.object({ orgId: id });

/**
 * Loads another member an admin wants to change. Nobody changes their own
 * role or status here (use Leave / Transfer ownership), and the owner is
 * protected (spec §5.6).
 */
async function targetMember(db: Firestore, orgId: string, caller: Caller, uid: string): Promise<Membership> {
  await requireActiveAdmin(db, orgId, caller.uid);
  if (uid === caller.uid) {
    fail('failed-precondition', 'self-change', 'You cannot change your own membership here.');
  }
  const snap = await db.doc(`orgs/${orgId}/members/${uid}`).get();
  const m = snap.data() as Membership | undefined;
  if (!m) fail('not-found', 'member-not-found', 'No such member.');
  if (m.role === 'owner') {
    fail('failed-precondition', 'owner-protected', 'The owner cannot be changed; transfer ownership first.');
  }
  return m;
}

export async function setMemberRoleImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof setMemberRoleInput>,
): Promise<{ ok: true }> {
  const m = await targetMember(db, input.orgId, caller, input.uid);
  if (m.role !== input.role) {
    await db.doc(`orgs/${input.orgId}/members/${input.uid}`).update({
      role: input.role,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await writeAudit(db, input.orgId, {
      actorUid: caller.uid,
      action: 'member.role',
      entity: 'member',
      entityId: input.uid,
      details: { from: m.role, to: input.role },
    });
  }
  return { ok: true };
}

export async function setMemberStatusImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof setMemberStatusInput>,
): Promise<{ ok: true }> {
  const m = await targetMember(db, input.orgId, caller, input.uid);
  if (m.status !== input.status) {
    await db.doc(`orgs/${input.orgId}/members/${input.uid}`).update({
      status: input.status,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await writeAudit(db, input.orgId, {
      actorUid: caller.uid,
      action: input.status === 'disabled' ? 'member.disable' : 'member.enable',
      entity: 'member',
      entityId: input.uid,
    });
  }
  return { ok: true };
}

export async function removeMemberImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof memberRefInput>,
): Promise<{ ok: true }> {
  const m = await targetMember(db, input.orgId, caller, input.uid);
  await removeMembership(db, input.orgId, input.uid);
  await writeAudit(db, input.orgId, {
    actorUid: caller.uid,
    action: 'member.remove',
    entity: 'member',
    entityId: input.uid,
    details: { email: m.email },
  });
  return { ok: true };
}

/** Owner hands the owner role to an active member and becomes admin. */
export async function transferOwnershipImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof memberRefInput>,
): Promise<{ ok: true }> {
  const { membership } = await requireActiveAdmin(db, input.orgId, caller.uid);
  if (membership.role !== 'owner') fail('permission-denied', 'not-owner', 'Only the owner can do this.');
  if (input.uid === caller.uid) fail('failed-precondition', 'self-change', 'You are already the owner.');
  const orgRef = db.doc(`orgs/${input.orgId}`);
  const targetRef = orgRef.collection('members').doc(input.uid);
  await db.runTransaction(async (tx) => {
    const target = (await tx.get(targetRef)).data() as Membership | undefined;
    if (!target) fail('not-found', 'member-not-found', 'No such member.');
    if (target.status !== 'active') fail('failed-precondition', 'member-not-found', 'The new owner must be active.');
    const now = FieldValue.serverTimestamp();
    tx.update(targetRef, { role: 'owner', updatedAt: now });
    tx.update(orgRef.collection('members').doc(caller.uid), { role: 'admin', updatedAt: now });
    tx.update(orgRef, { ownerUid: input.uid, updatedAt: now });
  });
  await writeAudit(db, input.orgId, {
    actorUid: caller.uid,
    action: 'org.transferOwnership',
    entity: 'member',
    entityId: input.uid,
  });
  return { ok: true };
}

/** A member (not the owner) leaves; works in suspended organizations too. */
export async function leaveOrganizationImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof orgRefInput>,
): Promise<{ ok: true }> {
  const { membership } = await requireMember(db, input.orgId, caller.uid);
  if (membership.role === 'owner') {
    fail('failed-precondition', 'owner-must-transfer', 'Transfer ownership or delete the organization first.');
  }
  await removeMembership(db, input.orgId, caller.uid);
  await writeAudit(db, input.orgId, {
    actorUid: caller.uid,
    action: 'member.leave',
    entity: 'member',
    entityId: caller.uid,
  });
  return { ok: true };
}

export const setMemberRole = callable(setMemberRoleInput, (c, i) => setMemberRoleImpl(getFirestore(), c, i));
export const setMemberStatus = callable(setMemberStatusInput, (c, i) => setMemberStatusImpl(getFirestore(), c, i));
export const removeMember = callable(memberRefInput, (c, i) => removeMemberImpl(getFirestore(), c, i));
export const transferOwnership = callable(memberRefInput, (c, i) => transferOwnershipImpl(getFirestore(), c, i));
export const leaveOrganization = callable(orgRefInput, (c, i) => leaveOrganizationImpl(getFirestore(), c, i));
