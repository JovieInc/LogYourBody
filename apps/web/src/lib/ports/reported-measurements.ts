const MAX_BYTES = 16 * 1024;
const MAX_ITEMS = 64;
const MAX_DEPTH = 6;
const MAX_NODES = 512;
const KNOWN_KINDS = new Set([
  'lean_mass',
  'fat_free_mass',
  'muscle_mass',
  'skeletal_muscle_mass',
  'unidentified_mass',
]);

function isObject(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  // Request JSON may come from another JavaScript realm.
  return prototype === null || Object.getPrototypeOf(prototype) === null;
}

// Future fields are retained as bounded JSON, never interpreted as measurements.
function isBoundedJSON(value: unknown): boolean {
  const pending: Array<{ value: unknown; depth: number }> = [{ value, depth: 0 }];
  let visited = 0;
  while (pending.length) {
    const current = pending.pop()!;
    if (++visited > MAX_NODES || current.depth > MAX_DEPTH) return false;
    const item = current.value;
    if (item === null || typeof item === 'boolean') continue;
    if (typeof item === 'number') {
      if (!Number.isFinite(item)) return false;
    } else if (typeof item === 'string') {
      if (Buffer.byteLength(item, 'utf8') > MAX_BYTES) return false;
    } else if (Array.isArray(item)) {
      if (item.length > MAX_ITEMS) return false;
      pending.push(...item.map((child) => ({ value: child, depth: current.depth + 1 })));
    } else if (isObject(item)) {
      const entries = Object.entries(item);
      if (entries.length > MAX_ITEMS || entries.some(([key]) => key.length > 160)) return false;
      pending.push(...entries.map(([, child]) => ({ value: child, depth: current.depth + 1 })));
    } else {
      return false;
    }
  }
  return Buffer.byteLength(JSON.stringify(value), 'utf8') <= MAX_BYTES;
}

function boundedLabel(value: unknown, maximum: number): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= maximum;
}

/** Admission validation only; success does not establish a future kind's semantics. */
export function isSafeReportedMeasurements(value: unknown): boolean {
  if (!isObject(value) || !isBoundedJSON(value)) return false;
  if (!Number.isSafeInteger(value.schema_version) || Number(value.schema_version) < 1) return false;
  if (!Array.isArray(value.items) || value.items.length > MAX_ITEMS) return false;
  return value.items.every((item: unknown) => {
    if (!isObject(item) || !boundedLabel(item.kind, 80)) return false;
    if (value.schema_version !== 1 || !KNOWN_KINDS.has(item.kind)) return true;
    return (
      typeof item.value === 'number' &&
      Number.isFinite(item.value) &&
      item.value > 0 &&
      (item.unit === null ||
        (typeof item.unit === 'string' && ['kg', 'lb', 'g'].includes(item.unit))) &&
      boundedLabel(item.reported_label, 160) &&
      (item.reported_unit === null || boundedLabel(item.reported_unit, 32))
    );
  });
}

export function hasSafeReportedMeasurements(record: Record<string, unknown>): boolean {
  return (
    !Object.hasOwn(record, 'reported_measurements') ||
    isSafeReportedMeasurements(record.reported_measurements)
  );
}
