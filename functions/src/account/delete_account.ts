import { getAuth } from 'firebase-admin/auth';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { z } from 'zod';

import type { Caller } from '../lib/auth.ts';
import { writeAudit } from '../lib/audit.ts';
import { callable } from '../lib/callable.ts';
import { fail } from '../lib/errors.ts';
import { removeMembership } from '../members/remove.ts';

export const deleteAccountInput = z.object({}).strict();

/**
 * Deletes the caller's account (spec §4.5, required by both stores): every
 * membership (name and email go with it; hours stay with the employer,
 * linked only to a random user ID), the profile, then the sign-in account.
 * An owner must transfer ownership or delete the organization first.
 */
export async function deleteAccountImpl(
  db: Firestore,
  caller: Caller,
  deleteAuthUser: (uid: string) => Promise<void>,
): Promise<{ ok: true }> {
  const memberships = await db.collectionGroup('members').where('uid', '==', caller.uid).get();
  if (memberships.docs.some((d) => d.get('role') === 'owner')) {
    fail('failed-precondition', 'owner-must-transfer', 'Transfer ownership or delete your organizations first.');
  }
  for (const m of memberships.docs) {
    const orgId = m.ref.parent.parent!.id;
    await removeMembership(db, orgId, caller.uid);
    await writeAudit(db, orgId, {
      actorUid: caller.uid,
      action: 'account.delete',
      entity: 'member',
      entityId: caller.uid,
    });
  }
  await db.recursiveDelete(db.doc(`users/${caller.uid}`));
  await deleteAuthUser(caller.uid);
  logger.info('Account deleted', { uid: caller.uid, memberships: memberships.size });
  return { ok: true };
}

export const deleteAccount = callable(deleteAccountInput, (c) =>
  deleteAccountImpl(getFirestore(), c, (uid) => getAuth().deleteUser(uid)),
);
