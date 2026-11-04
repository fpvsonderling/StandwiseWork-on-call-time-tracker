import type { Firestore } from 'firebase-admin/firestore';

import { fail } from './errors.ts';
import { personName } from './names.ts';

export interface Profile {
  firstName: string;
  lastName: string;
  email: string;
}

/** Spec §4: organization actions need a completed "Your name" profile. */
export async function requireProfile(db: Firestore, uid: string): Promise<Profile> {
  const data = (await db.doc(`users/${uid}`).get()).data();
  const first = personName.safeParse(data?.firstName);
  const last = personName.safeParse(data?.lastName);
  if (!data || !first.success || !last.success || typeof data.email !== 'string') {
    fail('failed-precondition', 'profile-required', 'Complete your profile first.');
  }
  return { firstName: first.data, lastName: last.data, email: data.email };
}
