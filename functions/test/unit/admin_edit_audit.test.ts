import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { adminEditAudit } from '../../src/summaries/triggers.ts';

describe('adminEditAudit', () => {
  const t1 = Timestamp.fromMillis(1_000);
  const t2 = Timestamp.fromMillis(2_000);
  const base = { uid: 'carol', description: 'x' };
  const signed = (at: Timestamp, extra: Record<string, unknown> = {}) => ({
    ...base,
    editedBy: 'bob',
    editedByName: 'Bob Test',
    editedAt: at,
    ...extra,
  });

  it('logs a new admin edit against the entry owner', () => {
    assert.deepEqual(adminEditAudit('e1', base, signed(t1, { editComment: 'Fix' })), {
      actorUid: 'bob',
      action: 'entry.edit',
      entity: 'member',
      entityId: 'carol',
      details: { entryId: 'e1', comment: 'Fix' },
    });
    assert.equal(adminEditAudit('e1', signed(t1), signed(t2))?.details?.comment, undefined);
  });

  it('ignores writes without a new edit time', () => {
    assert.equal(adminEditAudit('e1', base, base), null);
    assert.equal(adminEditAudit('e1', signed(t1), { ...signed(t1), description: 'y' }), null);
    assert.equal(adminEditAudit('e1', signed(t1), undefined), null);
  });
});
