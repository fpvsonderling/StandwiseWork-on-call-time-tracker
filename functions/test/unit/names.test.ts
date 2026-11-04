import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { fullName, personName } from '../../src/lib/names.ts';

describe('personName', () => {
  it('accepts Unicode letters, spaces, hyphens and apostrophes', () => {
    for (const ok of ['Łukasz', "O'Neil", 'Anna Maria', 'Jean-Luc', 'Zoë', 'D’Angelo']) {
      assert.equal(personName.safeParse(ok).success, true, ok);
    }
  });

  it('trims and collapses whitespace', () => {
    assert.equal(personName.parse('  Anna   Maria '), 'Anna Maria');
  });

  it('rejects empty, too long and invalid names', () => {
    for (const bad of ['', '   ', 'x'.repeat(51), 'Ann4', "'-", 'A<b>']) {
      assert.equal(personName.safeParse(bad).success, false, JSON.stringify(bad));
    }
  });

  it('counts characters, not UTF-16 units', () => {
    assert.equal(personName.safeParse('Ł'.repeat(50)).success, true);
  });
});

describe('fullName', () => {
  it('joins first and last name', () => {
    assert.equal(fullName(' Anna ', 'Kowalska'), 'Anna Kowalska');
  });
});
