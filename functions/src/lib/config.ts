import { setGlobalOptions } from 'firebase-functions/v2';

/** Closest region to the `eur3` Firestore location (docs/DECISIONS.md). */
export const REGION = 'europe-west1';

setGlobalOptions({ region: REGION, maxInstances: 10 });
