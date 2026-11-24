import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

/** The "No project" rate key (lib/domain/projects.dart `noProjectKey`). */
export const NO_PROJECT_KEY = '_none';

type RateData = Record<string, unknown> | undefined;

export interface RatePair {
  work: number;
  standby: number;
}

function minor(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? Math.round(v) : 0;
}

export function ratePair(d: RateData): RatePair {
  return { work: minor(d?.workRateMinor), standby: minor(d?.standbyRateMinor) };
}

/**
 * The rate an entry should get after a member's rate changed from [before]
 * to [after], or `null` to leave it alone (D-054).
 *
 * An entry follows the new rate while an admin has not approved it and it
 * still has the old rate or none (0). An entry with any other rate was set
 * by hand in the entry editor and keeps it; approved entries are locked.
 */
export function repricedRate(
  entry: Record<string, unknown>,
  before: RatePair,
  after: RatePair,
): number | null {
  if (entry.deleted === true) return null;
  if (typeof entry.approvedBy === 'string') return null;
  const standby = entry.type === 'standby';
  const oldRate = standby ? before.standby : before.work;
  const newRate = standby ? after.standby : after.work;
  const current = minor(entry.rateMinor);
  if (current === newRate) return null;
  if (current !== oldRate && current !== 0) return null;
  return newRate;
}

/**
 * Sets the new rate on [uid]'s entries of [projectKey] that follow it.
 * Returns how many entries changed.
 */
export async function repriceEntries(
  db: Firestore,
  orgId: string,
  uid: string,
  projectKey: string,
  before: RatePair,
  after: RatePair,
): Promise<number> {
  const projectId = projectKey === NO_PROJECT_KEY ? null : projectKey;
  const snap = await db
    .collection(`orgs/${orgId}/entries`)
    .where('uid', '==', uid)
    .where('projectId', '==', projectId)
    .get();
  const changes = snap.docs.flatMap((d) => {
    const rate = repricedRate(d.data(), before, after);
    return rate === null ? [] : [{ ref: d.ref, rate }];
  });
  for (let i = 0; i < changes.length; i += 400) {
    const batch = db.batch();
    for (const c of changes.slice(i, i + 400)) {
      batch.update(c.ref, { rateMinor: c.rate, updatedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
  return changes.length;
}

/**
 * Firestore trigger: when a member's rate for a project changes, their
 * entries of that project that are not approved yet use the new rate, so
 * amounts in Timer, reports and Team are recalculated (D-054).
 */
export const onRateWritten = onDocumentWritten(
  'orgs/{orgId}/members/{uid}/rates/{projectId}',
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    const { orgId, uid, projectId } = event.params;
    await repriceEntries(
      getFirestore(),
      orgId,
      uid,
      projectId,
      ratePair(event.data?.before.data()),
      ratePair(after),
    );
  },
);
