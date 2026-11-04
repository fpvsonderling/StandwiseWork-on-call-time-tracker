import { createHash, randomInt } from 'node:crypto';

/** No 0/O, 1/I/L: easy to read aloud and type (spec §5.6, e.g. `K7M2-9QXP`). */
export const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_LENGTH = 8;

/** A new random code, formatted `XXXX-XXXX`. */
export function generateInviteCode(): string {
  let raw = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    raw += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return `${raw.slice(0, 4)}-${raw.slice(4)}`;
}

/**
 * Accepts what people actually type: lower case, spaces, missing or extra
 * dashes. Returns the 8 code characters, or null if it can't be a code.
 */
export function normalizeInviteCode(input: string): string | null {
  const raw = input.toUpperCase().replace(/[\s-]/g, '');
  if (raw.length !== CODE_LENGTH) return null;
  for (const c of raw) {
    if (!CODE_ALPHABET.includes(c)) return null;
  }
  return raw;
}

/** Only the hash is stored, so a database read never reveals usable codes. */
export function hashInviteCode(normalized: string): string {
  return createHash('sha256').update(`standwise-invite:${normalized}`).digest('hex');
}
