export type DailyStepDeletionInput = {
  record: Record<string, unknown> & { id: string; date: string };
  day_start: string;
  day_end: string;
  time_zone: string;
};

export type DailyStepDeletionMarker = {
  schema_version: 1;
  deleted_at: string;
  day_start: string;
  day_end: string;
  time_zone: string;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/;
const HOUR = 60 * 60 * 1000;

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function instant(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  const match = ISO.exec(value);
  if (!match) return null;
  const [, y, m, d, h, min, sec] = match;
  const year = Number(y),
    month = Number(m),
    day = Number(d);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > days[month - 1]! ||
    Number(h) > 23 ||
    Number(min) > 59 ||
    Number(sec) > 59
  )
    return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function wallTime(formatter: Intl.DateTimeFormat, value: number) {
  const parts = Object.fromEntries(
    formatter.formatToParts(value).map((part) => [part.type, part.value]),
  );
  const year = Number(parts.year),
    month = Number(parts.month),
    day = Number(parts.day);
  const wall = new Date(0);
  wall.setUTCFullYear(year, month - 1, day);
  wall.setUTCHours(Number(parts.hour), Number(parts.minute), Number(parts.second), 0);
  return { day: `${parts.year}-${parts.month}-${parts.day}`, wall: wall.getTime() };
}

/** Verify a captured local day, including a midnight gap or repeated clock hour.
 * The original record date is retained; neither its zone nor its instant is rewritten.
 */
export function isValidDailyStepDeletion(input: unknown): input is DailyStepDeletionInput {
  if (
    !object(input) ||
    !object(input.record) ||
    typeof input.record.id !== 'string' ||
    !UUID.test(input.record.id) ||
    typeof input.time_zone !== 'string' ||
    !/^[A-Za-z_]+(?:\/[A-Za-z0-9_+.-]+)*$/.test(input.time_zone) ||
    input.time_zone.length > 100
  )
    return false;
  const start = instant(input.day_start),
    end = instant(input.day_end),
    recorded = instant(input.record.date);
  if (
    start === null ||
    end === null ||
    recorded === null ||
    end <= start ||
    end - start > 48 * HOUR ||
    recorded < start ||
    recorded >= end
  )
    return false;
  try {
    const formatter = new Intl.DateTimeFormat('en-US-u-ca-gregory-nu-latn', {
      timeZone: input.time_zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    const first = wallTime(formatter, start);
    if (
      wallTime(formatter, start - 1).day === first.day ||
      wallTime(formatter, end - 1).day !== first.day ||
      wallTime(formatter, end).day === first.day ||
      wallTime(formatter, recorded).day !== first.day
    )
      return false;

    // Check each clock segment and both sides of offset transitions. Merely
    // checking duration or endpoint dates misses midnight clock changes.
    const offset = (value: number) =>
      wallTime(formatter, value).wall - Math.floor(value / 1000) * 1000;
    const matches = (value: number) => wallTime(formatter, value).day === first.day;
    const checkSegments = (from: number, until: number, expected: boolean) => {
      for (let left = from; left < until; left += HOUR) {
        const right = Math.min(left + HOUR, until) - 1;
        if (matches(left) !== expected || matches(right) !== expected) return false;
        const initialOffset = offset(left);
        if (initialOffset === offset(right)) continue;
        let low = left,
          high = right;
        while (high - low > 1) {
          const middle = Math.floor((low + high) / 2);
          if (offset(middle) === initialOffset) low = middle;
          else high = middle;
        }
        if (matches(high - 1) !== expected || matches(high) !== expected) return false;
      }
      return true;
    };
    // Some historical midnight rollbacks briefly entered a date, returned to
    // the previous date, then entered it again. Neither partial occurrence is
    // the whole day. Check adjacent clock segments as well as the envelope.
    return (
      checkSegments(start, end, true) &&
      checkSegments(start - 48 * HOUR, start, false) &&
      checkSegments(end, end + 48 * HOUR, false)
    );
  } catch {
    return false;
  }
}
