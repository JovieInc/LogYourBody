import { describe, expect, it } from 'vitest';

import {
  UserDataDeletionError,
  accountDeletionTargets,
  deleteUserDatabaseRows,
} from '../../../supabase/functions/delete-user-assets/account-deletion';

class MockDeleteBuilder {
  constructor(
    private readonly table: string,
    private readonly failures: ReadonlyMap<string, unknown>,
    private readonly calls: string[],
  ) {}

  async eq(column: string, value: string): Promise<{ error?: unknown }> {
    this.calls.push(`${this.table}.${column}=${value}`);
    const error = this.failures.get(this.table);
    return error ? { error } : {};
  }
}

function createMockSupabase(failures: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const failureMap = new Map(Object.entries(failures));

  return {
    calls,
    client: {
      from(table: string) {
        return {
          delete() {
            return new MockDeleteBuilder(table, failureMap, calls);
          },
        };
      },
    },
  };
}

describe('deleteUserDatabaseRows', () => {
  it('deletes account-owned tables in dependency-safe order', async () => {
    const mock = createMockSupabase();

    const results = await deleteUserDatabaseRows(mock.client, 'user_123', {
      error: () => undefined,
    });

    expect(results.every((result) => result.success)).toBe(true);
    expect(mock.calls).toEqual([
      'data_exports.user_id=user_123',
      'progress_photos.user_id=user_123',
      'dexa_results.user_id=user_123',
      'glp1_dose_logs.user_id=user_123',
      'glp1_medications.user_id=user_123',
      'daily_metrics.user_id=user_123',
      'body_metrics.user_id=user_123',
      'email_subscriptions.user_id=user_123',
      'profiles.id=user_123',
    ]);
  });

  it('allows optional export cleanup to fail without blocking core deletion', async () => {
    const mock = createMockSupabase({
      data_exports: { message: 'invalid input syntax for type uuid' },
    });

    const results = await deleteUserDatabaseRows(mock.client, 'user_123', {
      error: () => undefined,
    });

    expect(results.find((result) => result.table === 'data_exports')).toMatchObject({
      required: false,
      success: false,
    });
    expect(results.find((result) => result.table === 'profiles')).toMatchObject({
      required: true,
      success: true,
    });
  });

  it('attempts every table before throwing on required-table failures', async () => {
    const mock = createMockSupabase({
      body_metrics: { message: 'permission denied for table body_metrics' },
    });

    await expect(
      deleteUserDatabaseRows(mock.client, 'user_123', { error: () => undefined }),
    ).rejects.toBeInstanceOf(UserDataDeletionError);

    expect(mock.calls.at(-1)).toBe('profiles.id=user_123');
  });

  it('keeps profile deletion last', () => {
    expect(accountDeletionTargets.at(-1)).toMatchObject({
      table: 'profiles',
      column: 'id',
      required: true,
    });
  });

  it('rejects blank user ids', async () => {
    const mock = createMockSupabase();

    await expect(
      deleteUserDatabaseRows(mock.client, '   ', { error: () => undefined }),
    ).rejects.toThrow('Cannot delete account data without a user id');
  });
});
