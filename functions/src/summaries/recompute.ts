import { FieldValue, type Firestore, type Timestamp } from 'firebase-admin/firestore';

import { buildDays, type EntryForSummary } from './summary.ts';

export interface SummaryKey {
  uid: string;
  monthKey: string;
}

/**
 * Rewrites `orgs/{orgId}/summaries/{uid}_{monthKey}` from that month's
 * entries, or deletes it when there are none. Does nothing for an
 * organization that no longer exists (it is being deleted).
 */
export async function recomputeSummary(db: Firestore, orgId: string, key: SummaryKey): Promise<'written' | 'deleted' | 'skipped'> {
  const org = await db.doc(`orgs/${orgId}`).get();
  if (!org.exists) return 'skipped';
  const timeZone = (org.get('settings.timezone') as string | undefined) ?? 'Europe/Warsaw';
  const snap = await db
    .collection(`orgs/${orgId}/entries`)
    .where('uid', '==', key.uid)
    .where('monthKey', '==', key.monthKey)
    .get();
  const entries: EntryForSummary[] = snap.docs.map((d) => ({
    type: d.get('type'),
    start: (d.get('start') as Timestamp).toDate(),
    durationMin: d.get('durationMin') ?? 0,
    rateMinor: d.get('rateMinor') ?? 0,
    projectId: d.get('projectId') ?? null,
    deleted: d.get('deleted') === true,
  }));
  const ref = db.doc(`orgs/${orgId}/summaries/${key.uid}_${key.monthKey}`);
  const days = buildDays(entries, key.monthKey, timeZone);
  if (Object.keys(days).length === 0) {
    await ref.delete();
    return 'deleted';
  }
  await ref.set({
    uid: key.uid,
    monthKey: key.monthKey,
    days,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return 'written';
}

/** Summaries an entry change affects: before and after may differ. */
export function affectedKeys(
  before: { uid?: unknown; monthKey?: unknown } | undefined,
  after: { uid?: unknown; monthKey?: unknown } | undefined,
): SummaryKey[] {
  const keys = new Map<string, SummaryKey>();
  for (const d of [before, after]) {
    if (typeof d?.uid === 'string' && typeof d.monthKey === 'string') {
      keys.set(`${d.uid}_${d.monthKey}`, { uid: d.uid, monthKey: d.monthKey });
    }
  }
  return [...keys.values()];
}
