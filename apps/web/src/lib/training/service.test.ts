import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { pullAllTrainingRecords } from './service';

const row = (id: string): NativeProductRecord => ({
  id,
  deleted_at: null,
  server_updated_at: '2026-01-01T00:00:00.000Z',
});

describe('training record pagination', () => {
  it('loads every page using the returned update-time cursor', async () => {
    const nextCursor = { since: '2026-01-01T00:00:00.000Z', after_id: 'first' };
    const pages = [
      { records: [row('first')], deleted_ids: [], next_cursor: nextCursor },
      { records: [row('second')], deleted_ids: [], next_cursor: null },
    ];
    const pull = jest.fn(async () => pages.shift()!);
    const records = { pull } as unknown as NativeProductRecordsPort;

    await expect(pullAllTrainingRecords(records, 'subject-a', 'logged_sets')).resolves.toEqual([
      row('first'),
      row('second'),
    ]);
    expect(pull).toHaveBeenCalledTimes(2);
    expect(pull).toHaveBeenNthCalledWith(2, 'subject-a', 'logged_sets', {
      ...nextCursor,
      limit: 500,
    });
  });

  it('fails closed if the record cursor repeats', async () => {
    const nextCursor = { since: '2026-01-01T00:00:00.000Z', after_id: 'first' };
    const pull = jest.fn(async () => ({ records: [], deleted_ids: [], next_cursor: nextCursor }));
    const records = { pull } as unknown as NativeProductRecordsPort;

    await expect(pullAllTrainingRecords(records, 'subject-a', 'training_sessions')).rejects.toThrow(
      'training_records_pagination_stalled',
    );
  });
});
