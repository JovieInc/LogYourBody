import { ConflictResolver } from '../conflict-resolver';
import type { DailyMetrics } from '@/lib/db/indexed-db';
import type { BodyMetrics, UserProfile } from '@/types/body-metrics';

function bodyMetrics(overrides: Partial<BodyMetrics> = {}): BodyMetrics {
  return {
    id: 'metric_1',
    user_id: 'user_1',
    date: '2026-06-20T12:00:00.000Z',
    created_at: '2026-06-20T12:00:00.000Z',
    updated_at: '2026-06-20T12:00:00.000Z',
    ...overrides,
  };
}

function dailyMetrics(overrides: Partial<DailyMetrics> = {}): DailyMetrics {
  return {
    id: 'daily_1',
    user_id: 'user_1',
    date: new Date('2026-06-20T12:00:00.000Z'),
    created_at: new Date('2026-06-20T12:00:00.000Z'),
    updated_at: new Date('2026-06-20T12:00:00.000Z'),
    ...overrides,
  };
}

function profile(overrides: Partial<UserProfile> = {}): UserProfile {
  return {
    id: 'user_1',
    email: 'test@example.com',
    email_verified: true,
    onboarding_completed: true,
    settings: {},
    created_at: '2026-06-20T12:00:00.000Z',
    updated_at: '2026-06-20T12:00:00.000Z',
    ...overrides,
  };
}

describe('ConflictResolver', () => {
  it('uses the newest updated_at timestamp for last-write-wins body metrics', () => {
    const resolver = new ConflictResolver('last-write-wins');
    const local = bodyMetrics({ weight: 180, updated_at: '2026-06-20T12:00:00.000Z' });
    const remote = bodyMetrics({ weight: 181, updated_at: '2026-06-20T12:00:02.000Z' });

    expect(resolver.resolveBodyMetrics({ local, remote })).toBe(remote);
  });

  it('merges body metrics without dropping photo, notes, or composition data', () => {
    const resolver = new ConflictResolver('merge');
    const local = bodyMetrics({
      notes: 'new local note',
      waist: 32,
      updated_at: '2026-06-20T12:00:02.000Z',
    });
    const remote = bodyMetrics({
      body_fat_method: 'dexa',
      body_fat_percentage: 17.5,
      notes: 'older server note',
      photo_url: 'https://assets.example/progress.jpg',
      updated_at: '2026-06-20T12:00:00.000Z',
    });

    expect(resolver.resolveBodyMetrics({ local, remote })).toEqual(
      expect.objectContaining({
        body_fat_method: 'dexa',
        body_fat_percentage: 17.5,
        notes: 'new local note\n---\nolder server note',
        photo_url: 'https://assets.example/progress.jpg',
        waist: 32,
        updated_at: '2026-06-20T12:00:02.000Z',
      }),
    );
  });

  it('merges daily metrics by keeping the highest step count and both notes', () => {
    const resolver = new ConflictResolver('merge');
    const local = dailyMetrics({
      notes: 'watch steps',
      steps: 6200,
      updated_at: new Date('2026-06-20T12:00:00.000Z'),
    });
    const remote = dailyMetrics({
      notes: 'phone note',
      steps: 5900,
      updated_at: new Date('2026-06-20T12:00:02.000Z'),
    });

    expect(resolver.resolveDailyMetrics({ local, remote })).toEqual(
      expect.objectContaining({
        notes: 'phone note\n---\nwatch steps',
        steps: 6200,
        updated_at: new Date('2026-06-20T12:00:02.000Z'),
      }),
    );
  });

  it('merges profiles by preserving one-sided identity fields and nested settings', () => {
    const resolver = new ConflictResolver('merge');
    const local = profile({
      settings: { units: { weight: 'lbs' } },
      updated_at: '2026-06-20T12:00:02.000Z',
      username: 'local-name',
    });
    const remote = profile({
      full_name: 'Remote Name',
      settings: { notifications: { daily_reminder: true } },
      updated_at: '2026-06-20T12:00:00.000Z',
    });

    expect(resolver.resolveProfile({ local, remote })).toEqual(
      expect.objectContaining({
        full_name: 'Remote Name',
        settings: {
          notifications: { daily_reminder: true },
          units: { weight: 'lbs' },
        },
        username: 'local-name',
        updated_at: '2026-06-20T12:00:02.000Z',
      }),
    );
  });

  it('only reports timestamp conflicts when both sides changed after the last sync', () => {
    const lastSyncTime = new Date('2026-06-20T12:00:01.000Z');
    const local = bodyMetrics({ updated_at: '2026-06-20T12:00:02.000Z' });
    const remote = bodyMetrics({ updated_at: '2026-06-20T12:00:03.000Z' });
    const oldRemote = bodyMetrics({ updated_at: '2026-06-20T12:00:00.000Z' });

    expect(ConflictResolver.hasConflict(local, remote, lastSyncTime)).toBe(true);
    expect(ConflictResolver.hasConflict(local, oldRemote, lastSyncTime)).toBe(false);
  });
});
