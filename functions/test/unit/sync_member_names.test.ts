import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { namesChanged } from '../../src/profile/sync_member_names.ts';

describe('namesChanged', () => {
  const p = { firstName: 'Anna', lastName: 'Kowalska', email: 'a@example.com' };

  it('is false for deletes and unrelated edits', () => {
    assert.equal(namesChanged(p, undefined), false);
    assert.equal(namesChanged(p, { ...p }), false);
  });

  it('is true for a new profile or a changed name or email', () => {
    assert.equal(namesChanged(undefined, p), true);
    assert.equal(namesChanged(p, { ...p, lastName: 'Nowak' }), true);
    assert.equal(namesChanged(p, { ...p, email: 'b@example.com' }), true);
  });
});
