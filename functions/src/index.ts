// Standwise Cloud Functions (spec §7). Each function lives in its own module;
// this file only wires them up.
import { initializeApp } from 'firebase-admin/app';

import './lib/config.ts';

initializeApp();

export { onUserProfileUpdated } from './profile/on_user_profile_updated.ts';
export { createOrganization } from './orgs/create_organization.ts';
export { acceptInvite, createInvite, resendInvite, revokeInvite } from './invites/invites.ts';
export { deleteOrganization } from './orgs/delete_organization.ts';
export {
  leaveOrganization,
  removeMember,
  setMemberRole,
  setMemberStatus,
  transferOwnership,
} from './members/members.ts';
export { deleteAccount } from './account/delete_account.ts';
export { onEntryWritten, purgeDeletedEntries } from './summaries/triggers.ts';
