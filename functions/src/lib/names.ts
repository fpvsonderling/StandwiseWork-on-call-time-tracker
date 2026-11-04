import { z } from 'zod';

/** Same rules as lib/domain/person_name.dart and firestore.rules (spec §4.2). */
export const MAX_NAME_LENGTH = 50;

const NAME_PATTERN = /^[\p{L}\p{M}' ’-]+$/u;

/** Trims and collapses inner whitespace. */
export function normalizeName(input: string): string {
  return input.trim().replace(/\s+/gu, ' ');
}

export const personName = z
  .string()
  .transform(normalizeName)
  .pipe(
    z
      .string()
      .min(1)
      .refine((v) => [...v].length <= MAX_NAME_LENGTH, 'too long')
      .refine((v) => NAME_PATTERN.test(v) && /\p{L}/u.test(v), 'invalid characters'),
  );

/** "First Last", as shown in reports, CSV and Team. */
export function fullName(first: string, last: string): string {
  return normalizeName(`${first} ${last}`);
}
