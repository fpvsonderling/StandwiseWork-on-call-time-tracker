import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { z } from 'zod';

import { requireOwner } from '../lib/access.ts';
import type { Caller } from '../lib/auth.ts';
import { callable } from '../lib/callable.ts';
import { fail } from '../lib/errors.ts';

export const deleteOrganizationInput = z.object({
  orgId: z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/),
  /** The organization's name, typed again by the owner. */
  confirmName: z.string().max(100),
});

/**
 * Owner deletes the organization and everything in it (spec §7). The
 * organization document goes first, so entry triggers that fire during the
 * recursive delete see no organization and don't recreate summaries.
 */
export async function deleteOrganizationImpl(
  db: Firestore,
  caller: Caller,
  input: z.output<typeof deleteOrganizationInput>,
): Promise<{ ok: true }> {
  const { org } = await requireOwner(db, input.orgId, caller.uid);
  if ((org.name as string).trim() !== input.confirmName.trim()) {
    fail('invalid-argument', 'name-mismatch', 'The name does not match.');
  }
  const orgRef = db.doc(`orgs/${input.orgId}`);
  await orgRef.delete();
  await db.recursiveDelete(orgRef);
  logger.info('Organization deleted', { orgId: input.orgId, by: caller.uid });
  return { ok: true };
}

export const deleteOrganization = callable(deleteOrganizationInput, (c, i) =>
  deleteOrganizationImpl(getFirestore(), c, i),
);
