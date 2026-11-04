import { FieldValue, type Firestore } from 'firebase-admin/firestore';

export interface AuditEntry {
  actorUid: string;
  action: string;
  entity: string;
  entityId: string;
  details?: Record<string, unknown>;
}

/** Appends to `orgs/{orgId}/auditLog` (spec §6). Only functions write it. */
export async function writeAudit(db: Firestore, orgId: string, entry: AuditEntry): Promise<void> {
  await db.collection('orgs').doc(orgId).collection('auditLog').add({
    ...entry,
    details: entry.details ?? {},
    at: FieldValue.serverTimestamp(),
  });
}
