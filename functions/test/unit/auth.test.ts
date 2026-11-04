import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { HttpsError } from 'firebase-functions/v2/https';

import { requireVerifiedCaller } from '../../src/lib/auth.ts';

function request(token: Record<string, unknown> | null) {
  return {
    auth: token === null ? undefined : { uid: 'u1', token: token as never, rawToken: '' },
  };
}

describe('requireVerifiedCaller', () => {
  it('returns uid and lower-cased email from the auth token', () => {
    assert.deepEqual(
      requireVerifiedCaller(request({ email: 'Anna@Example.com', email_verified: true })),
      { uid: 'u1', email: 'anna@example.com' },
    );
  });

  it('rejects signed-out callers', () => {
    assert.throws(
      () => requireVerifiedCaller(request(null)),
      (e: unknown) => e instanceof HttpsError && e.code === 'unauthenticated',
    );
  });

  it('rejects unverified or missing emails', () => {
    for (const token of [{ email: 'a@example.com', email_verified: false }, { email_verified: true }]) {
      assert.throws(
        () => requireVerifiedCaller(request(token)),
        (e: unknown) => e instanceof HttpsError && e.code === 'failed-precondition',
      );
    }
  });
});
