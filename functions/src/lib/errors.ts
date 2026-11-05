import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/**
 * Machine-readable reasons the app maps to its own messages
 * (lib/data/firebase/callable_client.dart). Never show `message` to users.
 */
export type FailureReason =
  | 'profile-required'
  | 'not-admin'
  | 'org-not-found'
  | 'org-read-only'
  | 'org-limit'
  | 'already-member'
  | 'invite-pending'
  | 'invite-not-found'
  | 'invite-expired'
  | 'invite-used'
  | 'invite-email-mismatch'
  | 'member-not-found'
  | 'owner-protected'
  | 'self-change'
  | 'not-owner'
  | 'owner-must-transfer'
  | 'name-mismatch';

export function fail(code: FunctionsErrorCode, reason: FailureReason, message: string): never {
  throw new HttpsError(code, message, { reason });
}
