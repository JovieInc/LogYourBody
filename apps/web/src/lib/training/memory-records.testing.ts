import type { TrainingMutationsPort } from '@/lib/ports/training-mutations';
import { isProgramSetup } from './engine';
import type { TrainingProgramSetup } from './types';
import { recoveryRecordBasis } from './recovery-records';
import { trainingRequestHash } from './revisions';
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

  private readonly owners = new Map<string, { id: string; generation: number }>();
  private incarnation = 0;
  recreateOwner(subject: string) {
    const id = `00000000-0000-4000-8000-${String(++this.incarnation).padStart(12, '0')}`;
    this.owners.set(subject, { id, generation: 0 });
  }
  readonly trainingMutations: TrainingMutationsPort = {
    commitRecoveryTrial: async ({
      subject,
      admission,
      expectedRecords,
      expectedRevision,
      record,
    }) => {
      const owner = this.owners.get(subject);
      const setup = this.data.training_feedback.get(admission.setupId);
      if (!owner) return { kind: 'owner_missing' };
      if (
        owner.id !== admission.ownerId ||
        owner.generation !== admission.generation ||
        !setup ||
        setup.deleted_at !== null ||
        (setup.programRevisionId ?? null) !== admission.revisionId
      )
        return { kind: 'stale_admission' };
      const rows = ['training_sessions', 'logged_sets', 'training_feedback'].flatMap((collection) =>
        [...this.data[collection as NativeProductRecordCollection].values()]
          .filter((row) => row.user_id === subject && row.deleted_at === null)
          .map((row) => ({ ...row, collection })),
      );
      if (trainingRequestHash(recoveryRecordBasis(rows)) !== trainingRequestHash(expectedRecords))
        return { kind: 'record_conflict' };
      const prior = this.data.training_feedback.get(String(record.id));
      if (
        (prior ? Number(prior.revision) : null) !== expectedRevision ||
        record.record_type !== 'recovery_trial' ||
        record.programSetupId !== setup.id ||
        record.programRevisionId !== (setup.programRevisionId ?? null)
      )
        return { kind: 'record_conflict' };
      // No suspension between the source check and the single CAS write.
      const stored = {
        ...record,
        id: String(record.id),
        user_id: subject,
        deleted_at: null,
        server_updated_at: String(record.updatedAt),
      } as NativeProductRecord;
      this.data.training_feedback.set(stored.id, stored);
      return { kind: 'saved', record: stored };
    },
    captureAdmission: async (subject) => {
      const owner = this.owners.get(subject);
      const setup = [...this.data.training_feedback.values()]
        .filter(
          (row) =>
            row.user_id === subject &&
            row.deleted_at === null &&
            row.record_type === 'program_setup',
        )
        .filter((row): row is NativeProductRecord & TrainingProgramSetup => isProgramSetup(row))
        .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))[0];
      if (!owner || !setup) return null;
      return {
        ownerId: owner.id,
        generation: owner.generation,
        setupId: setup.id,
        revisionId: setup.programRevisionId ?? null,
      };
    },
    commit: async ({ subject, admission, action, record }) => {
      const owner = this.owners.get(subject);
      if (!owner) return { kind: 'owner_missing' };
      const setup = this.data.training_feedback.get(admission.setupId);
      if (
        owner.id !== admission.ownerId ||
        owner.generation !== admission.generation ||
        !setup ||
        setup.deleted_at !== null ||
        (setup.programRevisionId ?? null) !== admission.revisionId
      )
        return { kind: 'stale_admission' };
      const sessionId = String(action.startsWith('session_') ? record.id : record.sessionId);
      const session = this.data.training_sessions.get(sessionId);
      if (
        session &&
        (session.user_id !== subject ||
          session.deleted_at !== null ||
          session.programSetupId !== admission.setupId ||
          (session.programRevisionId ?? null) !== admission.revisionId)
      )
        return { kind: 'session_conflict' };
      if (!session && action !== 'session_insert') return { kind: 'session_conflict' };
      if (
        action.startsWith('session_') &&
        (record.programSetupId !== admission.setupId ||
          (record.programRevisionId ?? null) !== admission.revisionId)
      )
        return { kind: 'session_conflict' };
      // No suspension between admission and the synchronous in-memory write.
      if (action === 'set_insert') {
        const prior = this.data.logged_sets.get(String(record.id));
        if (!prior && session?.status !== 'in_progress') return { kind: 'session_conflict' };
        const saved = await this.insertTrainingSet(subject, record);
        return saved ? { kind: 'saved', record: saved } : { kind: 'record_conflict' };
      }
      if (action === 'set_correct') {
        const expectedRevision = Number(record.expectedRevision);
        const payload = { ...record };
        delete payload.expectedRevision;
        const saved = await this.correctTrainingSet(
          subject,
          String(record.id),
          expectedRevision,
          payload,
        );
        return saved ? { kind: 'saved', record: saved } : { kind: 'record_conflict' };
      }
      if (action === 'session_update' && record.status === 'completed') {
        const prescription = record.prescription as { executionRevision?: number } | undefined;
        const loggedSetCount = [...this.data.logged_sets.values()].filter(
          (candidate) =>
            candidate.user_id === subject &&
            candidate.deleted_at === null &&
            candidate.sessionId === record.id,
        ).length;
        const saved = await this.updateTrainingSession(
          subject,
          String(record.id),
          Number(prescription?.executionRevision ?? 0),
          loggedSetCount,
          record,
        );
        return saved ? { kind: 'saved', record: saved } : { kind: 'record_conflict' };
      }
      if (
        action === 'session_update' &&
        (record.expectedExecutionRevision !== undefined ||
          record.expectedLoggedSetCount !== undefined)
      ) {
        const payload = { ...record };
        delete payload.expectedExecutionRevision;
        delete payload.expectedLoggedSetCount;
        const saved = await this.updateTrainingSession(
          subject,
          String(record.id),
          Number(record.expectedExecutionRevision),
          Number(record.expectedLoggedSetCount),
          payload,
        );
        return saved ? { kind: 'saved', record: saved } : { kind: 'record_conflict' };
      }
      if (action === 'swap_insert') {
        if (
          record.record_type !== 'exercise_swap' ||
          record.programSetupId !== admission.setupId ||
          (record.programRevisionId ?? null) !== admission.revisionId ||
          typeof record.fromExerciseId !== 'string' ||
          typeof record.toVariantId !== 'string' ||
          typeof record.blockId !== 'string'
        )
          return { kind: 'record_conflict' };
        if (
          !session ||
          session.record_type !== 'workout_session' ||
          session.status !== 'in_progress'
        )
          return { kind: 'session_conflict' };
      }
      const collection = action === 'feedback_insert' ? 'training_feedback' : 'training_sessions';
      const existing = this.data[collection].get(String(record.id));
      if (existing?.deleted_at) return { kind: 'record_conflict' };
      const result = await this.push(subject, collection, [record]);
      return result.records[0]
        ? { kind: 'saved', record: result.records[0] }
        : { kind: 'record_conflict' };
    },
  };

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

  async correctTrainingSet(
    subject: string,
    id: string,
    expectedRevision: number,
    record: Record<string, unknown>,
  ) {
    const existing = this.data.logged_sets.get(id);
    if (
      !existing ||
      existing.user_id !== subject ||
      existing.deleted_at !== null ||
      Number(existing.revision ?? 0) !== expectedRevision
    )
      return null;
    const stored = {
      ...record,
      id,
      user_id: subject,
      deleted_at: null,
      server_updated_at: '2026-01-10T12:00:01.000Z',
    } as NativeProductRecord;
    this.data.logged_sets.set(id, stored);
    return stored;
  }

  async updateTrainingSession(
    subject: string,
    id: string,
    expectedRevision: number,
    expectedLoggedSetCount: number,
    record: Record<string, unknown>,
  ) {
    const existing = this.data.training_sessions.get(id);
    const prescription = existing?.prescription as { executionRevision?: number } | undefined;
    const loggedSetCount = [...this.data.logged_sets.values()].filter(
      (candidate) =>
        candidate.user_id === subject &&
        candidate.deleted_at === null &&
        candidate.sessionId === id,
    ).length;
    if (
      !existing ||
      existing.user_id !== subject ||
      existing.deleted_at !== null ||
      Number(prescription?.executionRevision ?? 0) !== expectedRevision ||
      loggedSetCount !== expectedLoggedSetCount
    )
      return null;
    const stored = {
      ...record,
      id,
      user_id: subject,
      deleted_at: null,
      server_updated_at: '2026-01-10T12:00:01.000Z',
    } as NativeProductRecord;
    this.data.training_sessions.set(id, stored);
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
      if (collection === 'training_feedback' && record.record_type === 'program_setup') {
        if (!this.owners.has(subject)) this.recreateOwner(subject);
        this.owners.get(subject)!.generation += 1;
      }
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
    const owner = this.owners.get(subject);
    if (owner && ids.length) owner.generation += 1;
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
    this.owners.delete(subject);
    for (const records of Object.values(this.data)) {
      for (const [id, record] of records) if (record.user_id === subject) records.delete(id);
    }
  }
}
