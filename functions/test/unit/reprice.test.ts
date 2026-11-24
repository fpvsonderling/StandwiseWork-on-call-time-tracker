import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { ratePair, repricedRate } from '../../src/summaries/reprice.ts';

describe('repricedRate', () => {
  const before = { work: 10000, standby: 5000 };
  const after = { work: 15000, standby: 9000 };

  it('moves entries with the old rate to the new one, per type', () => {
    assert.equal(repricedRate({ type: 'work', rateMinor: 10000 }, before, after), 15000);
    assert.equal(repricedRate({ type: 'standby', rateMinor: 5000 }, before, after), 9000);
  });

  it('fills in entries saved without a rate', () => {
    assert.equal(repricedRate({ type: 'work', rateMinor: 0 }, before, after), 15000);
    assert.equal(repricedRate({ type: 'work' }, ratePair(undefined), after), 15000);
  });

  it('keeps a rate set by hand in the entry editor', () => {
    assert.equal(repricedRate({ type: 'work', rateMinor: 12000 }, before, after), null);
  });

  it('leaves approved and deleted entries alone', () => {
    assert.equal(repricedRate({ type: 'work', rateMinor: 0, approvedBy: 'admin' }, before, after), null);
    assert.equal(repricedRate({ type: 'work', rateMinor: 0, deleted: true }, before, after), null);
  });

  it('does nothing when the rate is already current', () => {
    assert.equal(repricedRate({ type: 'work', rateMinor: 15000 }, after, after), null);
  });
});
