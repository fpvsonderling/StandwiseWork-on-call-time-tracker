import { HttpsError } from 'firebase-functions/v2/https';
import type { z } from 'zod';

/** Parses callable input with [schema] or throws `invalid-argument`. */
export function parseInput<T extends z.ZodType>(schema: T, data: unknown): z.output<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpsError('invalid-argument', 'Invalid input.', {
      issues: result.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
    });
  }
  return result.data;
}
