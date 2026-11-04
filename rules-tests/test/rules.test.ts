import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  type Firestore,
} from 'firebase/firestore';

// Users: alice owns org A, bob is an admin, carol an employee, dave a
// disabled employee, erin belongs only to org B. mallory has no membership.
const ORG_A = 'orgA';
const ORG_B = 'orgB';
const ORG_SUSPENDED = 'orgS';

let env: RulesTestEnvironment;

function db(uid: string, verified = true): Firestore {
  return env
    .authenticatedContext(uid, {
      email: `${uid}@example.com`,
      email_verified: verified,
    })
    .firestore() as unknown as Firestore;
}

function anon(): Firestore {
  return env.unauthenticatedContext().firestore() as unknown as Firestore;
}

const settings = {
  currency: 'EUR',
  timezone: 'Europe/Warsaw',
  weekStart: 1,
  use24h: true,
  csvSeparator: ';',
  csvDecimal: ',',
};

function profile(uid: string, extra: Record<string, unknown> = {}) {
  return {
    firstName: 'Anna',
    lastName: 'Kowalska',
    email: `${uid}@example.com`,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

const t0 = Timestamp.fromDate(new Date('2026-11-02T08:00:00Z'));
const t8h = Timestamp.fromDate(new Date('2026-11-02T16:00:00Z'));

function entry(uid: string, extra: Record<string, unknown> = {}) {
  return {
    uid,
    projectId: 'p1',
    type: 'work',
    rateMinor: 5000,
    start: t0,
    end: t8h,
    durationMin: 480,
    description: 'Release',
    monthKey: '2026-11',
    deleted: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

function rate(extra: Record<string, unknown> = {}) {
  return {
    workRateMinor: 5000,
    standbyRateMinor: 1500,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

function project(extra: Record<string, unknown> = {}) {
  return {
    name: 'Night shift',
    client: 'ACME',
    color: 0xff3366cc,
    archived: false,
    deleted: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-standwise',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const a = ctx.firestore() as unknown as Firestore;
    const now = Timestamp.now();
    const org = (status: string) => ({
      name: 'Org',
      status,
      plan: 'trial',
      settings,
      ownerUid: 'alice',
      memberCount: 1,
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A), org('active'));
    await setDoc(doc(a, 'orgs', ORG_B), org('trial'));
    await setDoc(doc(a, 'orgs', ORG_SUSPENDED), org('suspended'));

    const member = (uid: string, role: string, status = 'active') => ({
      uid,
      role,
      status,
      firstName: uid,
      lastName: 'Test',
      email: `${uid}@example.com`,
      joinedAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A, 'members', 'alice'), member('alice', 'owner'));
    await setDoc(doc(a, 'orgs', ORG_A, 'members', 'bob'), member('bob', 'admin'));
    await setDoc(doc(a, 'orgs', ORG_A, 'members', 'carol'), member('carol', 'employee'));
    await setDoc(
      doc(a, 'orgs', ORG_A, 'members', 'dave'),
      member('dave', 'employee', 'disabled'),
    );
    await setDoc(doc(a, 'orgs', ORG_B, 'members', 'erin'), member('erin', 'owner'));
    await setDoc(
      doc(a, 'orgs', ORG_SUSPENDED, 'members', 'carol'),
      member('carol', 'admin'),
    );

    await setDoc(doc(a, 'orgs', ORG_A, 'members', 'carol', 'rates', 'p1'), {
      workRateMinor: 4000,
      standbyRateMinor: 1000,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A, 'projects', 'p1'), {
      ...project(),
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A, 'entries', 'carol-1'), {
      ...entry('carol'),
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A, 'entries', 'bob-1'), {
      ...entry('bob'),
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_B, 'entries', 'erin-1'), {
      ...entry('erin'),
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(a, 'orgs', ORG_A, 'invites', 'i1'), { email: 'x@example.com' });
    await setDoc(doc(a, 'users', 'carol'), {
      firstName: 'Carol',
      lastName: 'Test',
      email: 'carol@example.com',
      createdAt: now,
      updatedAt: now,
    });
  });
});

describe('users', () => {
  it('lets a user create their own profile', async () => {
    await assertSucceeds(setDoc(doc(db('mallory'), 'users', 'mallory'), profile('mallory')));
  });

  it('accepts Unicode letters, hyphens and apostrophes', async () => {
    await assertSucceeds(
      setDoc(
        doc(db('mallory'), 'users', 'mallory'),
        profile('mallory', { firstName: 'Łukasz', lastName: "O'Neil-Żak" }),
      ),
    );
  });

  it('rejects writing someone else’s profile', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'users', 'carol'), profile('mallory')));
  });

  it('rejects signed-out and unverified users', async () => {
    await assertFails(setDoc(doc(anon(), 'users', 'mallory'), profile('mallory')));
    await assertFails(
      setDoc(doc(db('mallory', false), 'users', 'mallory'), profile('mallory')),
    );
  });

  it('validates names', async () => {
    const d = doc(db('mallory'), 'users', 'mallory');
    for (const bad of ['', 'Ann4', ' Anna', 'x'.repeat(51), "'-", 'A<b>']) {
      await assertFails(setDoc(d, profile('mallory', { firstName: bad })));
    }
  });

  it('requires the auth email, server timestamps and known keys', async () => {
    const d = doc(db('mallory'), 'users', 'mallory');
    await assertFails(setDoc(d, profile('mallory', { email: 'other@example.com' })));
    await assertFails(setDoc(d, profile('mallory', { createdAt: Timestamp.now() })));
    await assertFails(setDoc(d, profile('mallory', { role: 'owner' })));
    const { lastName: _, ...noLastName } = profile('mallory');
    await assertFails(setDoc(d, noLastName));
  });

  it('keeps createdAt immutable on update', async () => {
    const d = doc(db('carol'), 'users', 'carol');
    await assertSucceeds(
      updateDoc(d, { firstName: 'Caroline', updatedAt: serverTimestamp() }),
    );
    await assertFails(
      updateDoc(d, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }),
    );
  });

  it('allows reading only your own profile, and no deletes', async () => {
    await assertSucceeds(getDoc(doc(db('carol'), 'users', 'carol')));
    await assertFails(getDoc(doc(db('bob'), 'users', 'carol')));
    await assertFails(deleteDoc(doc(db('carol'), 'users', 'carol')));
  });
});

describe('organizations', () => {
  it('is readable by members only', async () => {
    await assertSucceeds(getDoc(doc(db('carol'), 'orgs', ORG_A)));
    await assertSucceeds(getDoc(doc(db('dave'), 'orgs', ORG_A)));
    await assertFails(getDoc(doc(db('erin'), 'orgs', ORG_A)));
    await assertFails(getDoc(doc(db('mallory'), 'orgs', ORG_A)));
  });

  it('cannot be created or deleted by clients', async () => {
    await assertFails(
      setDoc(doc(db('mallory'), 'orgs', 'new'), { name: 'Mine', status: 'active' }),
    );
    await assertFails(deleteDoc(doc(db('alice'), 'orgs', ORG_A)));
  });

  it('lets admins edit name and settings only', async () => {
    const d = doc(db('bob'), 'orgs', ORG_A);
    await assertSucceeds(updateDoc(d, { name: 'New name', updatedAt: serverTimestamp() }));
    await assertSucceeds(
      updateDoc(d, { settings: { ...settings, csvSeparator: '\t' }, updatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(d, { status: 'suspended', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(d, { plan: 'pro', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(d, { ownerUid: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(
      updateDoc(d, { settings: { ...settings, currency: 'euro' }, updatedAt: serverTimestamp() }),
    );
  });

  it('rejects edits by employees and in suspended orgs', async () => {
    await assertFails(
      updateDoc(doc(db('carol'), 'orgs', ORG_A), { name: 'X', updatedAt: serverTimestamp() }),
    );
    await assertFails(
      updateDoc(doc(db('carol'), 'orgs', ORG_SUSPENDED), {
        name: 'X',
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('members', () => {
  it('lets members read themselves and admins read everyone', async () => {
    await assertSucceeds(getDoc(doc(db('carol'), 'orgs', ORG_A, 'members', 'carol')));
    await assertFails(getDoc(doc(db('carol'), 'orgs', ORG_A, 'members', 'bob')));
    await assertSucceeds(getDoc(doc(db('bob'), 'orgs', ORG_A, 'members', 'carol')));
    await assertSucceeds(getDocs(collection(db('bob'), 'orgs', ORG_A, 'members')));
    await assertFails(getDocs(collection(db('carol'), 'orgs', ORG_A, 'members')));
  });

  it('never lets a client write a membership', async () => {
    await assertFails(
      updateDoc(doc(db('carol'), 'orgs', ORG_A, 'members', 'carol'), { role: 'owner' }),
    );
    await assertFails(
      setDoc(doc(db('mallory'), 'orgs', ORG_A, 'members', 'mallory'), {
        role: 'employee',
        status: 'active',
      }),
    );
    await assertFails(
      updateDoc(doc(db('alice'), 'orgs', ORG_A, 'members', 'carol'), { role: 'admin' }),
    );
  });
});

describe('memberships across organizations', () => {
  it('lets a user list their own memberships and nobody else’s', async () => {
    const own = await assertSucceeds(
      getDocs(query(collectionGroup(db('carol'), 'members'), where('uid', '==', 'carol'))),
    );
    if (own.size !== 2) throw new Error(`expected 2 memberships, got ${own.size}`);
    await assertFails(
      getDocs(query(collectionGroup(db('carol'), 'members'), where('uid', '==', 'bob'))),
    );
    await assertFails(getDocs(collectionGroup(db('carol'), 'members')));
  });
});

describe('rates', () => {
  const rateDoc = (f: Firestore, uid: string, org = ORG_A) =>
    doc(f, 'orgs', org, 'members', uid, 'rates', 'p1');

  it('lets members set their own rates', async () => {
    await assertSucceeds(setDoc(rateDoc(db('carol'), 'carol'), rate()));
    await assertSucceeds(deleteDoc(rateDoc(db('carol'), 'carol')));
  });

  it('rejects other people’s rates and out-of-range values', async () => {
    await assertFails(setDoc(rateDoc(db('bob'), 'carol'), rate()));
    await assertFails(setDoc(rateDoc(db('carol'), 'carol'), rate({ workRateMinor: 1000001 })));
    await assertFails(setDoc(rateDoc(db('carol'), 'carol'), rate({ workRateMinor: -1 })));
    await assertFails(setDoc(rateDoc(db('carol'), 'carol'), rate({ workRateMinor: 10.5 })));
  });

  it('is read-only for disabled members and suspended orgs', async () => {
    await assertFails(setDoc(rateDoc(db('dave'), 'dave'), rate()));
    await assertFails(setDoc(rateDoc(db('carol'), 'carol', ORG_SUSPENDED), rate()));
  });

  it('is readable by the member and admins only', async () => {
    await assertSucceeds(getDoc(rateDoc(db('carol'), 'carol')));
    await assertSucceeds(getDoc(rateDoc(db('bob'), 'carol')));
    await assertFails(getDoc(rateDoc(db('dave'), 'carol')));
    await assertFails(getDoc(rateDoc(db('erin'), 'carol')));
  });
});

describe('projects', () => {
  it('is readable by members and writable by admins', async () => {
    await assertSucceeds(getDocs(collection(db('carol'), 'orgs', ORG_A, 'projects')));
    await assertFails(getDocs(collection(db('erin'), 'orgs', ORG_A, 'projects')));
    await assertSucceeds(setDoc(doc(db('bob'), 'orgs', ORG_A, 'projects', 'p2'), project()));
    await assertFails(setDoc(doc(db('carol'), 'orgs', ORG_A, 'projects', 'p2'), project()));
  });

  it('is soft-deleted only', async () => {
    await assertSucceeds(
      updateDoc(doc(db('bob'), 'orgs', ORG_A, 'projects', 'p1'), {
        deleted: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(db('alice'), 'orgs', ORG_A, 'projects', 'p1')));
  });
});

describe('entries', () => {
  const entries = (f: Firestore, org = ORG_A) => collection(f, 'orgs', org, 'entries');

  it('lets a member create their own valid entry', async () => {
    await assertSucceeds(setDoc(doc(entries(db('carol')), 'carol-2'), entry('carol')));
    await assertSucceeds(
      setDoc(doc(entries(db('carol')), 'carol-3'), entry('carol', { projectId: null })),
    );
  });

  it('rejects entries for someone else', async () => {
    await assertFails(setDoc(doc(entries(db('bob')), 'x'), entry('carol')));
  });

  it('validates time, duration, type, description and month', async () => {
    const d = doc(entries(db('carol')), 'carol-2');
    await assertFails(setDoc(d, entry('carol', { end: t0, durationMin: 0 })));
    const t25h = Timestamp.fromDate(new Date('2026-11-03T09:00:00Z'));
    await assertFails(setDoc(d, entry('carol', { end: t25h, durationMin: 1500 })));
    await assertFails(setDoc(d, entry('carol', { durationMin: 479 })));
    await assertFails(setDoc(d, entry('carol', { type: 'overtime' })));
    await assertFails(setDoc(d, entry('carol', { description: 'x'.repeat(501) })));
    await assertFails(setDoc(d, entry('carol', { monthKey: '2026-13' })));
    await assertFails(setDoc(d, entry('carol', { createdAt: Timestamp.now() })));
    await assertFails(setDoc(d, entry('carol', { amountMinor: 1 })));
  });

  it('allows exactly 24 hours', async () => {
    const t24h = Timestamp.fromDate(new Date('2026-11-03T08:00:00Z'));
    await assertSucceeds(
      setDoc(doc(entries(db('carol')), 'carol-2'), entry('carol', { end: t24h, durationMin: 1440 })),
    );
  });

  it('lets the owner of an entry edit it but keeps uid and createdAt fixed', async () => {
    const d = doc(entries(db('carol')), 'carol-1');
    await assertSucceeds(
      updateDoc(d, { description: 'Edited', deleted: true, updatedAt: serverTimestamp() }),
    );
    await assertFails(updateDoc(d, { uid: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(
      updateDoc(d, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }),
    );
  });

  it('never allows hard deletes', async () => {
    await assertFails(deleteDoc(doc(entries(db('carol')), 'carol-1')));
    await assertFails(deleteDoc(doc(entries(db('alice')), 'carol-1')));
  });

  it('keeps employees to their own entries', async () => {
    const f = db('carol');
    await assertSucceeds(getDoc(doc(entries(f), 'carol-1')));
    await assertFails(getDoc(doc(entries(f), 'bob-1')));
    await assertFails(getDocs(entries(f)));
    await assertSucceeds(getDocs(query(entries(f), where('uid', '==', 'carol'))));
    await assertFails(getDocs(query(entries(f), where('uid', '==', 'bob'))));
  });

  it('lets admins read everything but not edit other people’s entries', async () => {
    await assertSucceeds(getDocs(entries(db('bob'))));
    await assertFails(
      updateDoc(doc(entries(db('bob')), 'carol-1'), {
        description: 'Admin edit',
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(setDoc(doc(entries(db('alice')), 'carol-1'), entry('carol')));
  });

  it('isolates organizations', async () => {
    await assertFails(getDoc(doc(entries(db('alice'), ORG_B), 'erin-1')));
    await assertFails(getDocs(query(entries(db('erin')), where('uid', '==', 'erin'))));
    await assertFails(setDoc(doc(entries(db('erin')), 'erin-x'), entry('erin')));
  });

  it('is read-only for disabled members and suspended orgs', async () => {
    await assertFails(setDoc(doc(entries(db('dave')), 'dave-1'), entry('dave')));
    await assertFails(setDoc(doc(entries(db('carol'), ORG_SUSPENDED), 'c'), entry('carol')));
    await assertFails(setDoc(doc(entries(db('mallory')), 'm'), entry('mallory')));
  });
});

describe('timers', () => {
  const timer = (extra: Record<string, unknown> = {}) => ({
    projectId: 'p1',
    type: 'standby',
    description: '',
    start: Timestamp.now(),
    updatedAt: serverTimestamp(),
    ...extra,
  });

  it('lets a member start and stop their own timer', async () => {
    const d = doc(db('carol'), 'orgs', ORG_A, 'timers', 'carol');
    await assertSucceeds(setDoc(d, timer()));
    await assertSucceeds(deleteDoc(d));
  });

  it('rejects timers in the future or for someone else', async () => {
    const future = Timestamp.fromMillis(Date.now() + 60 * 60 * 1000);
    await assertFails(
      setDoc(doc(db('carol'), 'orgs', ORG_A, 'timers', 'carol'), timer({ start: future })),
    );
    await assertFails(setDoc(doc(db('bob'), 'orgs', ORG_A, 'timers', 'carol'), timer()));
  });

  it('hides other people’s timers from employees', async () => {
    await assertFails(getDoc(doc(db('carol'), 'orgs', ORG_A, 'timers', 'bob')));
    await assertSucceeds(getDoc(doc(db('bob'), 'orgs', ORG_A, 'timers', 'carol')));
  });
});

describe('function-only collections', () => {
  it('rejects every client write', async () => {
    for (const c of ['summaries', 'invites', 'auditLog']) {
      await assertFails(setDoc(doc(db('alice'), 'orgs', ORG_A, c, 'x'), { uid: 'alice' }));
    }
  });

  it('shows invites and the audit log to admins only', async () => {
    await assertSucceeds(getDoc(doc(db('bob'), 'orgs', ORG_A, 'invites', 'i1')));
    await assertFails(getDoc(doc(db('carol'), 'orgs', ORG_A, 'invites', 'i1')));
    await assertFails(getDocs(collection(db('carol'), 'orgs', ORG_A, 'auditLog')));
  });

  it('shows employees only their own summaries', async () => {
    const s = collection(db('carol'), 'orgs', ORG_A, 'summaries');
    await assertSucceeds(getDocs(query(s, where('uid', '==', 'carol'))));
    await assertFails(getDocs(s));
  });
});

describe('everything else', () => {
  it('keeps the outgoing mail queue closed', async () => {
    await assertFails(getDocs(collection(db('alice'), 'mail')));
    await assertFails(setDoc(doc(db('alice'), 'mail', 'x'), { to: ['a@example.com'] }));
  });

  it('is closed', async () => {
    await assertFails(getDoc(doc(db('alice'), 'anything', 'x')));
    await assertFails(setDoc(doc(db('alice'), 'anything', 'x'), { a: 1 }));
  });
});
