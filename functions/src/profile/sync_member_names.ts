import { FieldValue, type Firestore } from 'firebase-admin/firestore';

export interface ProfileNames {
  firstName?: unknown;
  lastName?: unknown;
  email?: unknown;
}

/** True when the fields copied into memberships differ. */
export function namesChanged(before: ProfileNames | undefined, after: ProfileNames | undefined): boolean {
  if (!after) return false;
  return (
    before?.firstName !== after.firstName ||
    before?.lastName !== after.lastName ||
    before?.email !== after.email
  );
}

/**
 * Copies first/last name and email from `users/{uid}` to every
 * `orgs/{orgId}/members/{uid}` of that user, so admins see the current name
 * in reports (spec §4.2). Idempotent: triggers run at least once.
 *
 * Membership documents carry a `uid` field so they can be found with one
 * collection-group query (docs/DECISIONS.md D-020).
 *
 * Returns the number of memberships updated.
 */
export async function syncMemberNames(db: Firestore, uid: string, profile: ProfileNames): Promise<number> {
  if (typeof profile.firstName !== 'string' || typeof profile.lastName !== 'string') {
    return 0;
  }
  const memberships = await db.collectionGroup('members').where('uid', '==', uid).get();
  const stale = memberships.docs.filter((d) => {
    const m = d.data();
    return (
      m.firstName !== profile.firstName ||
      m.lastName !== profile.lastName ||
      (typeof profile.email === 'string' && m.email !== profile.email)
    );
  });
  // A user belongs to a handful of organizations; 500 writes per batch.
  for (let i = 0; i < stale.length; i += 500) {
    const batch = db.batch();
    for (const d of stale.slice(i, i + 500)) {
      batch.update(d.ref, {
        firstName: profile.firstName,
        lastName: profile.lastName,
        ...(typeof profile.email === 'string' ? { email: profile.email } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  return stale.length;
}
