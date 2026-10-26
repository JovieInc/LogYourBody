import {
  admissionFailure,
  encodeWeightCursor,
  receiptFor,
  type CorrectWeightCommand,
  type CreateWeightCommand,
  type DeleteWeightCommand,
  type ListWeightQuery,
  type ListWeightResult,
  type MetricsGrant,
  type StoredReceipt,
  type StoredWeightEntry,
  type WeightActionResult,
  type WeightFailure,
  type WeightLifecyclePort,
} from './weight-lifecycle';

export class MemoryWeightLifecycle implements WeightLifecyclePort {
  readonly grants = new Map<string, MetricsGrant>();
  readonly entries = new Map<string, StoredWeightEntry>();
  readonly receipts = new Map<string, StoredReceipt>();
  readonly audits: Array<{
    action: string;
    record_id: string;
    operation_id: string;
    revision: number;
  }> = [];
  mutations = 0;
  private chain: Promise<unknown> = Promise.resolve();

  setGrant(grant: MetricsGrant) {
    this.grants.set(grant.subject, { ...grant });
  }

  async grant(subject: string): Promise<MetricsGrant | null> {
    const grant = this.grants.get(subject);
    return grant ? { ...grant } : null;
  }

  create(
    subject: string,
    ownerId: string,
    command: CreateWeightCommand,
    now: Date,
  ): Promise<WeightActionResult> {
    return this.locked(() => this.createLocked(subject, ownerId, command, now));
  }

  correct(
    subject: string,
    ownerId: string,
    command: CorrectWeightCommand,
    now: Date,
  ): Promise<WeightActionResult> {
    return this.locked(() => this.correctLocked(subject, ownerId, command, now));
  }

  remove(
    subject: string,
    ownerId: string,
    command: DeleteWeightCommand,
    now: Date,
  ): Promise<WeightActionResult> {
    return this.locked(() => this.deleteLocked(subject, ownerId, command, now));
  }

  async list(subject: string, query: ListWeightQuery): Promise<ListWeightResult> {
    const denied = this.deny(subject);
    if (denied) return denied;
    const rows = [...this.entries.values()]
      .filter((entry) => entry.subject === subject)
      .filter((entry) =>
        query.record_id ? entry.id === query.record_id : entry.deleted_at === null,
      )
      .sort(byMeasuredDesc)
      .filter((entry) => afterCursor(entry, query.cursor));
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      ok: true,
      records: page.map((entry) => ({ ...entry })),
      next_cursor:
        rows.length > query.limit && last
          ? encodeWeightCursor({ measured_at: last.measured_at, id: last.id })
          : null,
    };
  }

  private deny(subject: string, ownerId?: string): WeightFailure | null {
    const grant = this.grants.get(subject) ?? null;
    const failure = admissionFailure(true, grant);
    if (failure) return failure;
    if (!grant?.ownerId || (ownerId && grant.ownerId !== ownerId)) {
      return { ok: false, code: 'account_not_found' };
    }
    return null;
  }

  private replay(
    subject: string,
    operationId: string,
    requestHash: string,
  ): WeightActionResult | null {
    const existing = this.receipts.get(receiptKey(subject, operationId));
    if (!existing) return null;
    if (existing.request_hash !== requestHash) return { ok: false, code: 'idempotency_conflict' };
    return { ok: true, replayed: true, receipt: existing.receipt };
  }

  private createLocked(
    subject: string,
    ownerId: string,
    command: CreateWeightCommand,
    now: Date,
  ): WeightActionResult {
    const denied = this.deny(subject, ownerId);
    if (denied) return denied;
    const replay = this.replay(subject, command.operation_id, command.request_hash);
    if (replay) return replay;
    if (this.entries.has(command.record_id)) return { ok: false, code: 'record_conflict' };
    const entry = entryFrom(subject, command, now, 1, null);
    this.entries.set(entry.id, entry);
    return this.commit('create', command.operation_id, command.request_hash, entry);
  }

  private correctLocked(
    subject: string,
    ownerId: string,
    command: CorrectWeightCommand,
    now: Date,
  ): WeightActionResult {
    const denied = this.deny(subject, ownerId);
    if (denied) return denied;
    const replay = this.replay(subject, command.operation_id, command.request_hash);
    if (replay) return replay;
    const current = this.owned(subject, command.record_id);
    if (!current) return { ok: false, code: 'not_found' };
    if (current.revision !== command.expected_revision)
      return { ok: false, code: 'stale_revision' };
    if (current.deleted_at) return { ok: false, code: 'already_deleted' };
    const entry = entryFrom(subject, command, now, current.revision + 1, null);
    this.entries.set(entry.id, entry);
    return this.commit('correct', command.operation_id, command.request_hash, entry);
  }

  private deleteLocked(
    subject: string,
    ownerId: string,
    command: DeleteWeightCommand,
    now: Date,
  ): WeightActionResult {
    const denied = this.deny(subject, ownerId);
    if (denied) return denied;
    const replay = this.replay(subject, command.operation_id, command.request_hash);
    if (replay) return replay;
    const current = this.owned(subject, command.record_id);
    if (!current) return { ok: false, code: 'not_found' };
    if (current.revision !== command.expected_revision)
      return { ok: false, code: 'stale_revision' };
    if (current.deleted_at) return { ok: false, code: 'already_deleted' };
    const entry: StoredWeightEntry = {
      ...current,
      revision: current.revision + 1,
      deleted_at: now.toISOString(),
      client_updated_at: now.toISOString(),
      server_updated_at: now.toISOString(),
    };
    this.entries.set(entry.id, entry);
    return this.commit('delete', command.operation_id, command.request_hash, entry);
  }

  private owned(subject: string, id: string): StoredWeightEntry | null {
    const entry = this.entries.get(id);
    if (!entry || entry.subject !== subject) return null;
    return entry;
  }

  private commit(
    action: 'create' | 'correct' | 'delete',
    operationId: string,
    requestHash: string,
    entry: StoredWeightEntry,
  ): WeightActionResult {
    this.mutations += 1;
    const receipt = receiptFor(action, entry, operationId);
    this.receipts.set(receiptKey(entry.subject, operationId), {
      operation_id: operationId,
      request_hash: requestHash,
      receipt,
    });
    this.audits.push({
      action,
      record_id: entry.id,
      operation_id: operationId,
      revision: entry.revision,
    });
    return { ok: true, replayed: false, receipt };
  }

  private locked<T>(fn: () => T): Promise<T> {
    const run = this.chain.then(() => fn());
    this.chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
}

function receiptKey(subject: string, operationId: string) {
  return `${subject}:${operationId}`;
}

function entryFrom(
  subject: string,
  command: CreateWeightCommand,
  now: Date,
  revision: number,
  deletedAt: string | null,
): StoredWeightEntry {
  const stamp = now.toISOString();
  return {
    id: command.record_id,
    subject,
    revision,
    weight_kg: command.weight_kg,
    input_value: command.input_value,
    input_unit: command.input_unit,
    measured_at: command.measured_at,
    utc_offset_minutes: command.utc_offset_minutes,
    local_date: command.local_date,
    iana_zone: command.iana_zone,
    deleted_at: deletedAt,
    client_updated_at: stamp,
    server_updated_at: stamp,
    provenance: command.provenance,
  };
}

function byMeasuredDesc(a: StoredWeightEntry, b: StoredWeightEntry) {
  const diff = Date.parse(b.measured_at) - Date.parse(a.measured_at);
  if (diff !== 0) return diff;
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
}

function afterCursor(entry: StoredWeightEntry, cursor: ListWeightQuery['cursor']): boolean {
  if (!cursor) return true;
  const entryTime = Date.parse(entry.measured_at);
  const cursorTime = Date.parse(cursor.measured_at);
  if (entryTime < cursorTime) return true;
  if (entryTime > cursorTime) return false;
  return entry.id < cursor.id;
}

export function grantedSubject(
  subject: string,
  ownerId = '11111111-1111-4111-8111-111111111111',
): MetricsGrant {
  return {
    subject,
    ownerId,
    connected: true,
    consentGranted: true,
    entitled: true,
    revoked: false,
    accountDeleted: false,
  };
}
