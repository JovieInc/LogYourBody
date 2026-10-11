import {
  NATIVE_PRODUCT_RECORD_COLLECTIONS,
  type NativeProductRecord,
  type NativeProductRecordCollection,
  type NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';

/** In-memory records port for training and MCP tests. Rejects cross-subject id reuse. */
export class MemoryTrainingRecords implements NativeProductRecordsPort {
  private readonly data = Object.fromEntries(
    NATIVE_PRODUCT_RECORD_COLLECTIONS.map((collection) => [
      collection,
      new Map<string, NativeProductRecord>(),
    ]),
  ) as Record<NativeProductRecordCollection, Map<string, NativeProductRecord>>;

  async insertTrainingSet(subject: string, record: Record<string, unknown>) {
    const id = typeof record.id === 'string' ? record.id : '';
    if (!id) return null;
    const existing = this.data.logged_sets.get(id);
    if (existing) {
      return existing.user_id === subject && existing.deleted_at === null ? existing : null;
    }
    const stored = {
      ...record,
      id,
      user_id: subject,
      deleted_at: null,
      server_updated_at: '2026-01-10T12:00:00.000Z',
    } as NativeProductRecord;
    this.data.logged_sets.set(id, stored);
    return stored;
  }

  async push(
    subject: string,
    collection: NativeProductRecordCollection,
    records: Array<Record<string, unknown>>,
  ) {
    const accepted: NativeProductRecord[] = [];
    const rejected_ids: string[] = [];
    for (const record of records) {
      const id = typeof record.id === 'string' ? record.id : '';
      if (!id) continue;
      const existing = this.data[collection].get(id);
      if (existing && existing.user_id !== subject) {
        rejected_ids.push(id);
        continue;
      }
      const stored = {
        ...record,
        id,
        user_id: subject,
        deleted_at: null,
        server_updated_at: '2026-01-10T12:00:00.000Z',
      } as NativeProductRecord;
      this.data[collection].set(id, stored);
      accepted.push(stored);
    }
    return { records: accepted, rejected_ids };
  }

  async pull(subject: string, collection: NativeProductRecordCollection) {
    const records = [...this.data[collection].values()].filter(
      (record) => record.user_id === subject,
    );
    return {
      records,
      deleted_ids: records.filter((record) => record.deleted_at).map((record) => record.id),
      next_cursor: null,
    };
  }

  async remove(subject: string, collection: NativeProductRecordCollection, ids: string[]) {
    const deleted_ids: string[] = [];
    for (const id of ids) {
      const record = this.data[collection].get(id);
      if (record?.user_id === subject) {
        this.data[collection].set(id, { ...record, deleted_at: '2026-01-10T12:01:00.000Z' });
        deleted_ids.push(id);
      }
    }
    return { deleted_ids };
  }

  async endActiveGlp1Medications() {
    return { updated: 0 };
  }

  async listAll(subject: string) {
    return Object.fromEntries(
      NATIVE_PRODUCT_RECORD_COLLECTIONS.map((collection) => [
        collection,
        [...this.data[collection].values()].filter(
          (record) => record.user_id === subject && !record.deleted_at,
        ),
      ]),
    ) as Record<NativeProductRecordCollection, NativeProductRecord[]>;
  }

  async deleteAllForSubject(subject: string) {
    for (const records of Object.values(this.data)) {
      for (const [id, record] of records) if (record.user_id === subject) records.delete(id);
    }
  }
}
