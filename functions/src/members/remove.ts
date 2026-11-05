import { FieldValue, type Firestore } from 'firebase-admin/firestore';

/**
 * Removes one membership: the member document with its rates, the running
 * timer, and one from `memberCount`. Entries and summaries stay for the
 * employer's records (spec §4.5); without the member document they carry
 * no name or email.
 */
export async function removeMembership(db: Firestore, orgId: string, uid: string): Promise<void> {
  const orgRef = db.doc(`orgs/${orgId}`);
  const memberRef = orgRef.collection('members').doc(uid);
  await db.recursiveDelete(memberRef);
  await orgRef.collection('timers').doc(uid).delete();
  await orgRef.update({ memberCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
  // Don't leave the user pointing at an organization they left.
  const user = db.doc(`users/${uid}`);
  const snap = await user.get();
  if (snap.exists && snap.get('lastOrgId') === orgId) {
    await user.update({ lastOrgId: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
  }
}
