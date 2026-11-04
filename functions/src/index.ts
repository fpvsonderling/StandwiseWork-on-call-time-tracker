// Standwise Cloud Functions (spec §7). Each function lives in its own module;
// this file only wires them up. Later stages add the organization, invite,
// member and account callables.
import { initializeApp } from 'firebase-admin/app';

import './lib/config.ts';

initializeApp();

export { onUserProfileUpdated } from './profile/on_user_profile_updated.ts';
export { createOrganization } from './orgs/create_organization.ts';
export { acceptInvite, createInvite, resendInvite, revokeInvite } from './invites/invites.ts';
