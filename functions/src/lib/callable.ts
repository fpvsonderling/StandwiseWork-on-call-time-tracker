import { onCall, type CallableFunction, type CallableRequest } from 'firebase-functions/v2/https';
import type { z } from 'zod';

import { requireVerifiedCaller, type Caller } from './auth.ts';
import { parseInput } from './validation.ts';

/**
 * A callable with the common checks (spec §7): verified Firebase Auth caller
 * and zod-validated input. App Check enforcement is switched on in stage 8.
 */
export function callable<S extends z.ZodType, R>(
  schema: S,
  handler: (caller: Caller, input: z.output<S>, request: CallableRequest) => Promise<R>,
): CallableFunction<unknown, Promise<R>> {
  return onCall({ cors: false }, async (request) => {
    const caller = requireVerifiedCaller(request);
    const input = parseInput(schema, request.data);
    return handler(caller, input, request);
  });
}
