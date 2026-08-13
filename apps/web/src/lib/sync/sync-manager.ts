import { indexedDB } from '@/lib/db/indexed-db';
import type { BodyMetrics, UserProfile } from '@/types/body-metrics';
import type { DailyMetrics } from '@/lib/db/indexed-db';

export type SyncStatus = 'idle' | 'syncing' | 'success' | 'error';

interface SyncState {
  isSyncing: boolean;
  lastSyncDate: Date | null;
  syncStatus: SyncStatus;
  pendingSyncCount: number;
  error?: string;
}

class SyncManager {
  private state: SyncState = {
    isSyncing: false,
    lastSyncDate: null,
    syncStatus: 'idle',
    pendingSyncCount: 0,
  };

  private listeners: Set<(state: SyncState) => void> = new Set();
  private syncInterval: NodeJS.Timeout | null = null;
  private isOnline = typeof navigator !== 'undefined' ? navigator.onLine : true;

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('online', this.handleOnline);
      window.addEventListener('offline', this.handleOffline);
      this.startPeriodicSync();
      this.updatePendingCount();
    }
  }

  private updateState(updates: Partial<SyncState>) {
    this.state = { ...this.state, ...updates };
    this.notifyListeners();
  }

  private notifyListeners() {
    this.listeners.forEach((listener) => listener(this.state));
  }

  subscribe(listener: (state: SyncState) => void) {
    this.listeners.add(listener);
    listener(this.state);

    return () => {
      this.listeners.delete(listener);
    };
  }

  private handleOnline = () => {
    this.isOnline = true;
    this.syncIfNeeded();
  };

  private handleOffline = () => {
    this.isOnline = false;
  };

  private startPeriodicSync() {
    this.syncInterval = setInterval(
      () => {
        if (this.isOnline) {
          this.syncIfNeeded();
        }
      },
      15 * 60 * 1000,
    );
  }

  async syncIfNeeded() {
    if (!this.isOnline || this.state.isSyncing) return;

    const unsynced = await indexedDB.getUnsyncedItems();
    const totalUnsynced =
      unsynced.bodyMetrics.length + unsynced.dailyMetrics.length + unsynced.profiles.length;

    if (totalUnsynced > 0) {
      await this.syncAll();
    }
  }

  async syncAll() {
    if (this.state.isSyncing || !this.isOnline) return;

    this.updateState({ isSyncing: true, syncStatus: 'syncing' });

    try {
      const userId = await this.requireSubject();
      const unsynced = await indexedDB.getUnsyncedItems();
      let hasErrors = false;

      for (const profile of unsynced.profiles) {
        try {
          await this.syncProfile(profile, userId);
        } catch (error) {
          hasErrors = true;
          console.error('Profile sync error:', error);
        }
      }

      for (const metrics of unsynced.bodyMetrics) {
        try {
          await this.syncBodyMetrics(metrics, userId);
        } catch (error) {
          hasErrors = true;
          console.error('Body metrics sync error:', error);
        }
      }

      for (const metrics of unsynced.dailyMetrics) {
        try {
          await this.syncDailyMetrics(metrics, userId);
        } catch (error) {
          hasErrors = true;
          console.error('Daily metrics sync error:', error);
        }
      }

      this.updateState({
        isSyncing: false,
        lastSyncDate: new Date(),
        syncStatus: hasErrors ? 'error' : 'success',
        error: hasErrors ? 'Some items failed to sync' : undefined,
      });
    } catch (error) {
      this.updateState({
        isSyncing: false,
        syncStatus: 'error',
        error: error instanceof Error ? error.message : 'Sync failed',
      });
    }

    await this.updatePendingCount();
  }

  private async requireSubject(): Promise<string> {
    const response = await fetch('/api/profile', { cache: 'no-store' });
    if (!response.ok) throw new Error('User not authenticated');
    const payload = (await response.json()) as { profile?: { id?: string } };
    const id = payload.profile?.id;
    if (!id) throw new Error('User not authenticated');
    return id;
  }

  private async syncProfile(profile: UserProfile, userId: string) {
    const response = await fetch('/api/profile', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        fullName: profile.full_name,
        dateOfBirth:
          typeof profile.date_of_birth === 'string'
            ? profile.date_of_birth.slice(0, 10)
            : undefined,
        height: profile.height,
        heightUnit: profile.height_unit === 'ft' ? 'in' : profile.height_unit,
        gender: profile.gender,
        activityLevel: profile.activity_level,
        goalWeight: profile.goal_weight,
        goalWeightUnit: profile.goal_weight_unit,
        onboardingCompleted: profile.onboarding_completed,
      }),
    });
    if (!response.ok) throw new Error('Failed to sync profile');
    await indexedDB.markAsSynced('profiles', profile.id || userId);
    await indexedDB.updateSyncStatus('profiles', profile.id || userId, 'synced');
  }

  private async syncBodyMetrics(metrics: BodyMetrics, userId: string) {
    const date = metricDate(metrics.date);
    const response = await fetch('/api/body-metrics', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        date,
        weight: metrics.weight,
        weightUnit: metrics.weight_unit,
        bodyFatPercentage: metrics.body_fat_percentage,
        bodyFatMethod: metrics.body_fat_method,
        waist: metrics.waist,
        neck: metrics.neck,
        hip: metrics.hip,
        notes: metrics.notes,
        photoUrl: metrics.photo_url,
        dataSource: metrics.data_source || 'manual',
      }),
    });
    if (!response.ok) throw new Error('Failed to sync body metrics');
    await indexedDB.markAsSynced('bodyMetrics', metrics.id);
    await indexedDB.updateSyncStatus('bodyMetrics', metrics.id, 'synced');
    void userId;
  }

  private async syncDailyMetrics(metrics: DailyMetrics, userId: string) {
    const response = await fetch('/api/auth/mobile/sync/v1/daily-metrics', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify([
        {
          id: metrics.id,
          user_id: userId,
          date: metrics.date instanceof Date ? metrics.date.toISOString() : metrics.date,
          steps: metrics.steps,
          notes: metrics.notes,
        },
      ]),
    });
    if (!response.ok) throw new Error('Failed to sync daily metrics');
    await indexedDB.markAsSynced('dailyMetrics', metrics.id);
    await indexedDB.updateSyncStatus('dailyMetrics', metrics.id, 'synced');
  }

  async updatePendingCount() {
    const unsynced = await indexedDB.getUnsyncedItems();
    const count =
      unsynced.bodyMetrics.length + unsynced.dailyMetrics.length + unsynced.profiles.length;

    this.updateState({ pendingSyncCount: count });
  }

  async logWeight(weight: number, unit: string, notes?: string) {
    const userId = await this.requireSubject();

    const metrics: BodyMetrics = {
      id: crypto.randomUUID(),
      user_id: userId,
      date: new Date().toISOString(),
      weight,
      weight_unit: unit as 'kg' | 'lbs',
      notes,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    await indexedDB.saveBodyMetrics(metrics, userId);
    await this.updatePendingCount();

    if (this.isOnline) {
      this.syncIfNeeded();
    }

    return metrics;
  }

  async logDailyMetrics(steps?: number, notes?: string) {
    const userId = await this.requireSubject();

    const metrics: DailyMetrics = {
      id: crypto.randomUUID(),
      user_id: userId,
      date: new Date(),
      steps,
      notes,
      created_at: new Date(),
      updated_at: new Date(),
    };

    await indexedDB.saveDailyMetrics(metrics);
    await this.updatePendingCount();

    if (this.isOnline) {
      this.syncIfNeeded();
    }

    return metrics;
  }

  async getLocalBodyMetrics(from?: Date, to?: Date): Promise<BodyMetrics[]> {
    const userId = await this.requireSubject();
    return indexedDB.getBodyMetrics(userId, from, to);
  }

  async getLocalDailyMetrics(date: Date): Promise<DailyMetrics | null> {
    const userId = await this.requireSubject();
    return indexedDB.getDailyMetrics(userId, date);
  }

  destroy() {
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
      this.syncInterval = null;
    }

    if (typeof window !== 'undefined') {
      window.removeEventListener('online', this.handleOnline);
      window.removeEventListener('offline', this.handleOffline);
    }

    this.listeners.clear();
  }

  async clearAllData() {
    await indexedDB.clearAllData();
    this.updateState({
      lastSyncDate: null,
      syncStatus: 'idle',
      pendingSyncCount: 0,
      error: undefined,
    });
  }
}

function metricDate(value: string | Date): string {
  const iso = value instanceof Date ? value.toISOString() : value;
  return iso.slice(0, 10);
}

export const syncManager = new SyncManager();
