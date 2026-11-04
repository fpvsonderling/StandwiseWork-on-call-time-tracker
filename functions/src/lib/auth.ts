import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

export interface Caller {
  uid: string;
  email: string;
}

/**
 * Identity for a callable function, taken only from Firebase Auth (spec
 * §3.2). Never trust a uid or email sent in the request data.
 */
export function requireVerifiedCaller(request: Pick<CallableRequest, 'auth'>): Caller {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  const email = auth.token.email;
  if (typeof email !== 'string' || auth.token.email_verified !== true) {
    throw new HttpsError('failed-precondition', 'A verified email is required.');
  }
  return { uid: auth.uid, email: email.toLowerCase() };
}
