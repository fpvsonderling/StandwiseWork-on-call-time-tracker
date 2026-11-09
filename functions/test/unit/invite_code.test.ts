import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  CODE_ALPHABET,
  generateInviteCode,
  hashInviteCode,
  normalizeInviteCode,
} from '../../src/invites/code.ts';
import { inviteEmail } from '../../src/invites/email.ts';
import { createOrganizationInput } from '../../src/orgs/create_organization.ts';
import { createInviteInput } from '../../src/invites/invites.ts';

describe('invite codes', () => {
  it('look like K7M2-9QXP and use only unambiguous characters', () => {
    for (let i = 0; i < 200; i++) {
      const code = generateInviteCode();
      assert.match(code, /^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
      for (const c of code.replace('-', '')) assert.ok(CODE_ALPHABET.includes(c), c);
    }
  });

  it('normalizes what people type', () => {
    assert.equal(normalizeInviteCode('k7m2-9qxp'), 'K7M29QXP');
    assert.equal(normalizeInviteCode(' K7M2 9QXP '), 'K7M29QXP');
    assert.equal(normalizeInviteCode('K7M29QXP'), 'K7M29QXP');
  });

  it('rejects impossible codes', () => {
    for (const bad of ['', 'K7M2-9QX', 'K7M2-9QXPP', 'O0I1-LLLL', 'K7M2_9QXP']) {
      assert.equal(normalizeInviteCode(bad), null, bad);
    }
  });

  it('hashes deterministically without exposing the code', () => {
    const h = hashInviteCode('K7M29QXP');
    assert.equal(h, hashInviteCode('K7M29QXP'));
    assert.notEqual(h, hashInviteCode('K7M29QXQ'));
    assert.ok(!h.includes('K7M2'));
  });
});

describe('invite email', () => {
  it('contains the code and escapes HTML in names', () => {
    const mail = inviteEmail({
      to: 'a@example.com',
      orgName: '<ACME & Co>',
      inviterName: 'Anna Kowalska',
      code: 'K7M2-9QXP',
    });
    assert.deepEqual(mail.to, ['a@example.com']);
    assert.ok(mail.message.text.includes('K7M2-9QXP'));
    assert.ok(mail.message.html.includes('&lt;ACME &amp; Co&gt;'));
    assert.ok(!mail.message.html.includes('<ACME'));
    assert.ok(!mail.message.text.includes('standwise://'), 'no custom-scheme links');
    assert.ok(!mail.message.html.includes('standwise://'));
  });
});

describe('input validation', () => {
  it('accepts a normal organization and normalizes the currency', () => {
    const v = createOrganizationInput.parse({ name: ' ACME ', currency: 'pln', timezone: 'Europe/Warsaw' });
    assert.deepEqual(v, { name: 'ACME', currency: 'PLN', timezone: 'Europe/Warsaw' });
  });

  it('rejects bad organization input', () => {
    for (const bad of [
      { name: '', currency: 'EUR', timezone: 'Europe/Warsaw' },
      { name: 'x'.repeat(101), currency: 'EUR', timezone: 'Europe/Warsaw' },
      { name: 'A', currency: 'EURO', timezone: 'Europe/Warsaw' },
      { name: 'A', currency: 'EUR', timezone: 'Mars/Base' },
    ]) {
      assert.equal(createOrganizationInput.safeParse(bad).success, false, JSON.stringify(bad));
    }
  });

  it('lower-cases invite emails and only allows employee/admin', () => {
    assert.equal(
      createInviteInput.parse({ orgId: 'o1', email: ' Anna@Example.com ', role: 'admin' }).email,
      'anna@example.com',
    );
    assert.equal(createInviteInput.safeParse({ orgId: 'o1', email: 'a@example.com', role: 'owner' }).success, false);
    assert.equal(createInviteInput.safeParse({ orgId: 'o/1', email: 'a@example.com', role: 'admin' }).success, false);
    assert.equal(createInviteInput.safeParse({ orgId: 'o1', email: 'nope', role: 'admin' }).success, false);
  });
});
