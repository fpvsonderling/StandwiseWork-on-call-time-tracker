/**
 * Monthly summaries (spec §6): one document per member and month with
 * minutes and money per day and project, recomputed from that month's
 * entries (never incremented, because triggers run at least once).
 */

/** Key of entries without a project, as in the app (D-029). */
export const NO_PROJECT = '_none';

export interface EntryForSummary {
  type: 'work' | 'standby';
  start: Date;
  durationMin: number;
  rateMinor: number;
  projectId?: string | null;
  deleted?: boolean;
}

export interface Bucket {
  workMin: number;
  standbyMin: number;
  amountMinor: number;
  /** Number of entries (for the Team table). */
  count: number;
}

export interface DaySummary extends Bucket {
  byProject: Record<string, Bucket>;
}

/** Same rounding as lib/domain/money.dart `amountForDuration`. */
export function amountMinor(rateMinor: number, durationMin: number): number {
  return Math.floor((rateMinor * durationMin + 30) / 60);
}

/** `{year, month, day}` of [date] in [timeZone]. */
export function zonedDate(date: Date, timeZone: string): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const get = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  return { year: get('year'), month: get('month'), day: get('day') };
}

function daysInMonth(monthKey: string): number {
  const [y, m] = monthKey.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/**
 * The `DD` an entry counts on: its start day in the organization's
 * timezone. The month comes from the entry's `monthKey` (the device's local
 * month); when the two disagree (someone far from the organization's
 * timezone, near midnight at a month boundary) the day is clamped into that
 * month (D-031).
 */
export function dayKey(start: Date, monthKey: string, timeZone: string): string {
  const z = zonedDate(start, timeZone);
  const zonedKey = `${String(z.year).padStart(4, '0')}-${String(z.month).padStart(2, '0')}`;
  let day = z.day;
  if (zonedKey < monthKey) day = 1;
  if (zonedKey > monthKey) day = daysInMonth(monthKey);
  return String(day).padStart(2, '0');
}

function empty(): Bucket {
  return { workMin: 0, standbyMin: 0, amountMinor: 0, count: 0 };
}

function add(b: Bucket, e: EntryForSummary, amount: number): void {
  if (e.type === 'standby') b.standbyMin += e.durationMin;
  else b.workMin += e.durationMin;
  b.amountMinor += amount;
  b.count += 1;
}

export function buildDays(
  entries: Iterable<EntryForSummary>,
  monthKey: string,
  timeZone: string,
): Record<string, DaySummary> {
  const days: Record<string, DaySummary> = {};
  for (const e of entries) {
    if (e.deleted) continue;
    const key = dayKey(e.start, monthKey, timeZone);
    const day = (days[key] ??= { ...empty(), byProject: {} });
    const amount = amountMinor(e.rateMinor, e.durationMin);
    add(day, e, amount);
    add((day.byProject[e.projectId ?? NO_PROJECT] ??= empty()), e, amount);
  }
  return days;
}
