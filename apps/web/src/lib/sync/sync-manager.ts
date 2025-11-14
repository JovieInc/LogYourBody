import { indexedDB } from '@/lib/db/indexed-db';
import { createClient } from '@/lib/supabase/client';
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
    // Only setup browser-specific features on client side
    if (typeof window !== 'undefined') {
      // Listen for online/offline events
      window.addEventListener('online', this.handleOnline);
      window.addEventListener('offline', this.handleOffline);
      
      // Start periodic sync
      this.startPeriodicSync();
      
      // Update pending count on initialization
      this.updatePendingCount();
    }
  }

  // State management
  private updateState(updates: Partial<SyncState>) {
    this.state = { ...this.state, ...updates };
    this.notifyListeners();
  }

  private notifyListeners() {
    this.listeners.forEach(listener => listener(this.state));
  }

  subscribe(listener: (state: SyncState) => void) {
    this.listeners.add(listener);
    // Immediately notify with current state
    listener(this.state);
    
    // Return unsubscribe function
    return () => {
      this.listeners.delete(listener);
    };
  }

  // Network handlers
  private handleOnline = () => {
    this.isOnline = true;
    this.syncIfNeeded();
  };

  private handleOffline = () => {
    this.isOnline = false;
  };

  // Periodic sync
  private startPeriodicSync() {
    // Sync every 15 minutes when online (reduced from 5 for better battery life)
    this.syncInterval = setInterval(() => {
      if (this.isOnline) {
        this.syncIfNeeded();
      }
    }, 15 * 60 * 1000);
  }

  async syncIfNeeded() {
    if (!this.isOnline || this.state.isSyncing) return;

    const unsynced = await indexedDB.getUnsyncedItems();
    const totalUnsynced = 
      unsynced.bodyMetrics.length + 
      unsynced.dailyMetrics.length + 
      unsynced.profiles.length;

    if (totalUnsynced > 0) {
      await this.syncAll();
    }
  }

  async syncAll() {
    if (this.state.isSyncing || !this.isOnline) return;

    this.updateState({ isSyncing: true, syncStatus: 'syncing' });

    try {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      
      if (!user) {
        throw new Error('User not authenticated');
      }

      const unsynced = await indexedDB.getUnsyncedItems();
      let hasErrors = false;

      // Sync profiles
      for (const profile of unsynced.profiles) {
        try {
          await this.syncProfile(profile, user.id);
        } catch (error) {
          hasErrors = true;
          console.error('Profile sync error:', error);
        }
      }

      // Sync body metrics
      for (const metrics of unsynced.bodyMetrics) {
        try {
          await this.syncBodyMetrics(metrics, user.id);
        } catch (error) {
          hasErrors = true;
          console.error('Body metrics sync error:', error);
        }
      }

      // Sync daily metrics
      for (const metrics of unsynced.dailyMetrics) {
        try {
          await this.syncDailyMetrics(metrics, user.id);
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

  private async syncProfile(profile: UserProfile, userId: string) {
    const supabase = createClient();
    
    const { error } = await supabase
      .from('profiles')
      .upsert({
        ...profile,
        id: userId,
        updated_at: new Date().toISOString(),
      });

    if (error) throw error;

    await indexedDB.markAsSynced('profiles', profile.id || userId);
    await indexedDB.updateSyncStatus('profiles', profile.id || userId, 'synced');
  }

  private async syncBodyMetrics(metrics: BodyMetrics, userId: string) {
    const supabase = createClient();
    
    const { error } = await supabase
      .from('body_metrics')
      .upsert({
        ...metrics,
        user_id: userId,
        updated_at: new Date().toISOString(),
      });

    if (error) throw error;

    await indexedDB.markAsSynced('bodyMetrics', metrics.id);
    await indexedDB.updateSyncStatus('bodyMetrics', metrics.id, 'synced');
  }

  private async syncDailyMetrics(metrics: DailyMetrics, userId: string) {
    const supabase = createClient();
    
    const { error } = await supabase
      .from('daily_metrics')
      .upsert({
        ...metrics,
        user_id: userId,
        updated_at: new Date().toISOString(),
      });

    if (error) throw error;

    await indexedDB.markAsSynced('dailyMetrics', metrics.id);
    await indexedDB.updateSyncStatus('dailyMetrics', metrics.id, 'synced');
  }

  async updatePendingCount() {
    const unsynced = await indexedDB.getUnsyncedItems();
    const count = 
      unsynced.bodyMetrics.length + 
      unsynced.dailyMetrics.length + 
      unsynced.profiles.length;

    this.updateState({ pendingSyncCount: count });
  }

  // Public methods for data operations
  async logWeight(weight: number, unit: string, notes?: string) {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) throw new Error('User not authenticated');

    const metrics: BodyMetrics = {
      id: crypto.randomUUID(),
      user_id: user.id,
      date: new Date().toISOString(),
      weight,
      weight_unit: unit as 'kg' | 'lbs',
      notes,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    // Save to IndexedDB
    await indexedDB.saveBodyMetrics(metrics, user.id);
    await this.updatePendingCount();

    // Attempt immediate sync if online
    if (this.isOnline) {
      this.syncIfNeeded();
    }

    return metrics;
  }

  async logDailyMetrics(steps?: number, notes?: string) {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) throw new Error('User not authenticated');

    const metrics: DailyMetrics = {
      id: crypto.randomUUID(),
      user_id: user.id,
      date: new Date(),
      steps,
      notes,
      created_at: new Date(),
      updated_at: new Date(),
    };

    // Save to IndexedDB
    await indexedDB.saveDailyMetrics(metrics);
    await this.updatePendingCount();

    // Attempt immediate sync if online
    if (this.isOnline) {
      this.syncIfNeeded();
    }

    return metrics;
  }

  async getLocalBodyMetrics(from?: Date, to?: Date): Promise<BodyMetrics[]> {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) return [];

    return indexedDB.getBodyMetrics(user.id, from, to);
  }

  async getLocalDailyMetrics(date: Date): Promise<DailyMetrics | null> {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) return null;

    return indexedDB.getDailyMetrics(user.id, date);
  }

  // Cleanup
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

  // Clear all local data (for logout)
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

export const syncManager = new SyncManager();