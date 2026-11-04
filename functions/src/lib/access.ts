import type { DocumentData, Firestore } from 'firebase-admin/firestore';

import { fail } from './errors.ts';

export interface Membership {
  uid: string;
  role: 'owner' | 'admin' | 'employee';
  status: 'active' | 'disabled';
  firstName: string;
  lastName: string;
  email: string;
}

export interface OrgAccess {
  org: DocumentData;
  membership: Membership;
}

/**
 * The caller must be an active admin or owner of a writable (trial/active)
 * organization. Mirrors `isAdmin(orgId) && orgWritable(orgId)` in
 * firestore.rules.
 */
export async function requireActiveAdmin(db: Firestore, orgId: string, uid: string): Promise<OrgAccess> {
  const [orgSnap, memberSnap] = await Promise.all([
    db.doc(`orgs/${orgId}`).get(),
    db.doc(`orgs/${orgId}/members/${uid}`).get(),
  ]);
  const membership = memberSnap.data() as Membership | undefined;
  // Same answer for "no such org" and "not a member", so org IDs can't be probed.
  if (!orgSnap.exists || !membership) {
    fail('permission-denied', 'not-admin', 'Not an admin of this organization.');
  }
  if (membership.status !== 'active' || !['owner', 'admin'].includes(membership.role)) {
    fail('permission-denied', 'not-admin', 'Not an admin of this organization.');
  }
  const org = orgSnap.data()!;
  if (!['trial', 'active'].includes(org.status)) {
    fail('failed-precondition', 'org-read-only', 'This organization is read-only.');
  }
  return { org, membership };
}
