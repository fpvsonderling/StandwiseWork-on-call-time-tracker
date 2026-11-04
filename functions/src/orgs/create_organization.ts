import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { getFirestore } from 'firebase-admin/firestore';
import { z } from 'zod';

import type { Caller } from '../lib/auth.ts';
import { writeAudit } from '../lib/audit.ts';
import { callable } from '../lib/callable.ts';
import { fail } from '../lib/errors.ts';
import { requireProfile } from '../lib/profile.ts';

export const TRIAL_DAYS = 30;
/** Abuse guard: one person rarely owns more than a couple of companies. */
export const MAX_OWNED_ORGS = 5;

export const createOrganizationInput = z.object({
  name: z.string().trim().min(1).max(100),
  currency: z
    .string()
    .trim()
    .transform((v) => v.toUpperCase())
    .pipe(z.string().regex(/^[A-Z]{3}$/)),
  timezone: z
    .string()
    .trim()
    .min(1)
    .max(64)
    .refine((tz) => {
      try {
        new Intl.DateTimeFormat('en', { timeZone: tz });
        return true;
      } catch {
        return false;
      }
    }, 'unknown timezone'),
});

export type CreateOrganizationInput = z.output<typeof createOrganizationInput>;

/**
 * Creates an organization in `trial` and makes the caller its owner
 * (spec §4.3). Returns the new organization ID.
 */
export async function createOrganizationImpl(
  db: Firestore,
  caller: Caller,
  input: CreateOrganizationInput,
): Promise<{ orgId: string }> {
  const profile = await requireProfile(db, caller.uid);

  // A user has a handful of memberships; filter in code to need only the
  // single-field `members.uid` collection-group index.
  const memberships = await db.collectionGroup('members').where('uid', '==', caller.uid).get();
  const owned = memberships.docs.filter((d) => d.get('role') === 'owner').length;
  if (owned >= MAX_OWNED_ORGS) {
    fail('resource-exhausted', 'org-limit', 'Too many organizations.');
  }

  const orgRef = db.collection('orgs').doc();
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(orgRef, {
    name: input.name,
    status: 'trial',
    plan: 'trial',
    trialEndsAt: Timestamp.fromMillis(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000),
    settings: {
      currency: input.currency,
      timezone: input.timezone,
      weekStart: 1,
      use24h: true,
      csvSeparator: ',',
      csvDecimal: '.',
    },
    ownerUid: caller.uid,
    memberCount: 1,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(orgRef.collection('members').doc(caller.uid), {
    uid: caller.uid,
    role: 'owner',
    status: 'active',
    firstName: profile.firstName,
    lastName: profile.lastName,
    email: profile.email,
    joinedAt: now,
    updatedAt: now,
  });
  batch.update(db.doc(`users/${caller.uid}`), { lastOrgId: orgRef.id, updatedAt: now });
  await batch.commit();

  await writeAudit(db, orgRef.id, {
    actorUid: caller.uid,
    action: 'org.create',
    entity: 'org',
    entityId: orgRef.id,
    details: { name: input.name },
  });
  return { orgId: orgRef.id };
}

export const createOrganization = callable(createOrganizationInput, (caller, input) =>
  createOrganizationImpl(getFirestore(), caller, input),
);
