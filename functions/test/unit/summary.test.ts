import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { affectedKeys } from '../../src/summaries/recompute.ts';
import { amountMinor, buildDays, dayKey, NO_PROJECT } from '../../src/summaries/summary.ts';

describe('summaries', () => {
  it('rounds money like the app', () => {
    assert.equal(amountMinor(4550, 95), 7204);
    assert.equal(amountMinor(6000, 90), 9000);
    assert.equal(amountMinor(1, 29), 0);
    assert.equal(amountMinor(1, 30), 1);
  });

  it('counts an entry on its start day in the organization timezone', () => {
    // 23:30 UTC on 2 Nov is 00:30 on 3 Nov in Warsaw.
    assert.equal(dayKey(new Date('2026-11-02T23:30:00Z'), '2026-11', 'Europe/Warsaw'), '03');
    assert.equal(dayKey(new Date('2026-11-02T23:30:00Z'), '2026-11', 'UTC'), '02');
  });

  it('clamps a day from another month into the entry month', () => {
    // Warsaw already says 1 December, but the device said November.
    assert.equal(dayKey(new Date('2026-11-30T23:30:00Z'), '2026-11', 'Europe/Warsaw'), '30');
    assert.equal(dayKey(new Date('2026-11-30T23:30:00Z'), '2026-12', 'UTC'), '01');
  });

  it('adds days and projects, skipping deleted entries', () => {
    const days = buildDays(
      [
        { type: 'work', start: new Date('2026-11-02T08:00:00Z'), durationMin: 90, rateMinor: 6000, projectId: 'p1' },
        { type: 'standby', start: new Date('2026-11-02T18:00:00Z'), durationMin: 60, rateMinor: 1500 },
        { type: 'work', start: new Date('2026-11-03T08:00:00Z'), durationMin: 60, rateMinor: 6000, deleted: true },
      ],
      '2026-11',
      'Europe/Warsaw',
    );
    assert.deepEqual(Object.keys(days), ['02']);
    assert.deepEqual(
      { w: days['02'].workMin, s: days['02'].standbyMin, a: days['02'].amountMinor },
      { w: 90, s: 60, a: 10500 },
    );
    assert.deepEqual(days['02'].byProject.p1, { workMin: 90, standbyMin: 0, amountMinor: 9000 });
    assert.deepEqual(days['02'].byProject[NO_PROJECT], { workMin: 0, standbyMin: 60, amountMinor: 1500 });
  });

  it('a moved entry touches both months', () => {
    assert.deepEqual(affectedKeys({ uid: 'a', monthKey: '2026-10' }, { uid: 'a', monthKey: '2026-11' }), [
      { uid: 'a', monthKey: '2026-10' },
      { uid: 'a', monthKey: '2026-11' },
    ]);
    assert.deepEqual(affectedKeys(undefined, { uid: 'a', monthKey: '2026-11' }), [{ uid: 'a', monthKey: '2026-11' }]);
    assert.deepEqual(affectedKeys({ uid: 'a', monthKey: '2026-11' }, { uid: 'a', monthKey: '2026-11' }).length, 1);
  });
});
