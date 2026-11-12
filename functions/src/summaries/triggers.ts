import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { writeAudit, type AuditEntry } from '../lib/audit.ts';
import { affectedKeys, recomputeSummary } from './recompute.ts';

type EntryData = Record<string, unknown> | undefined;

function millis(v: unknown): number | null {
  return v instanceof Timestamp ? v.toMillis() : null;
}

/**
 * The audit entry for an admin's signed change to someone else's entry
 * (D-051): a write whose `editedAt` is new. `null` for every other write.
 */
export function adminEditAudit(entryId: string, before: EntryData, after: EntryData): AuditEntry | null {
  const at = millis(after?.editedAt);
  if (at === null || at === millis(before?.editedAt)) return null;
  const by = after?.editedBy;
  const owner = after?.uid;
  if (typeof by !== 'string' || typeof owner !== 'string') return null;
  const comment = after?.editComment;
  return {
    actorUid: by,
    action: 'entry.edit',
    entity: 'member',
    entityId: owner,
    details: { entryId, ...(typeof comment === 'string' ? { comment } : {}) },
  };
}

/**
 * Firestore trigger: recompute the summaries an entry change touches and
 * log admin edits.
 */
export const onEntryWritten = onDocumentWritten('orgs/{orgId}/entries/{entryId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const keys = affectedKeys(before, after);
  const db = getFirestore();
  for (const key of keys) {
    await recomputeSummary(db, event.params.orgId, key);
  }
  const audit = adminEditAudit(event.params.entryId, before, after);
  if (audit) await writeAudit(db, event.params.orgId, audit);
});

export const PURGE_AFTER_DAYS = 30;

/** Hard-deletes entries soft-deleted more than 30 days ago (spec §6). */
export async function purgeDeletedEntriesImpl(
  db: Firestore,
  now = Date.now(),
): Promise<number> {
  const cutoff = Timestamp.fromMillis(now - PURGE_AFTER_DAYS * 24 * 60 * 60 * 1000);
  let total = 0;
  for (;;) {
    const page = await db
      .collectionGroup('entries')
      .where('deleted', '==', true)
      .where('updatedAt', '<', cutoff)
      .limit(400)
      .get();
    if (page.empty) return total;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += page.size;
  }
}

export const purgeDeletedEntries = onSchedule(
  { schedule: 'every day 03:30', timeZone: 'Europe/Warsaw' },
  async () => {
    const count = await purgeDeletedEntriesImpl(getFirestore());
    logger.info('Purged soft-deleted entries', { count });
  },
);
