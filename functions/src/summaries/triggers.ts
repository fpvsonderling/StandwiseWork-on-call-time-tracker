import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { affectedKeys, recomputeSummary } from './recompute.ts';

/** Firestore trigger: recompute the summaries an entry change touches. */
export const onEntryWritten = onDocumentWritten('orgs/{orgId}/entries/{entryId}', async (event) => {
  const keys = affectedKeys(event.data?.before.data(), event.data?.after.data());
  const db = getFirestore();
  for (const key of keys) {
    await recomputeSummary(db, event.params.orgId, key);
  }
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
