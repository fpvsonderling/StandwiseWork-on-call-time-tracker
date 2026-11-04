import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

import { namesChanged, syncMemberNames, type ProfileNames } from './sync_member_names.ts';

/** Firestore trigger: keep membership names in sync with the profile. */
export const onUserProfileUpdated = onDocumentWritten('users/{uid}', async (event) => {
  const before = event.data?.before.data() as ProfileNames | undefined;
  const after = event.data?.after.data() as ProfileNames | undefined;
  if (!after || !namesChanged(before, after)) return;
  const count = await syncMemberNames(getFirestore(), event.params.uid, after);
  logger.info('Synced profile names to memberships', { uid: event.params.uid, count });
});
