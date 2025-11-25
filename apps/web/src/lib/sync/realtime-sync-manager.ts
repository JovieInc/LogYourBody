import { indexedDB } from '@/lib/db/indexed-db';
import { createClient } from '@/lib/supabase/client';
import type { BodyMetrics, UserProfile } from '@/types/body-metrics';
import type { DailyMetrics } from '@/lib/db/indexed-db';
import { ConflictResolver } from './conflict-resolver';
import type { RealtimeChannel, RealtimePostgresChangesPayload } from '@supabase/supabase-js';

export type SyncStatus = 'idle' | 'syncing' | 'success' | 'error' | 'offline';

interface SyncState {
  isSyncing: boolean;
  lastSyncDate: Date | null;
  syncStatus: SyncStatus;
  pendingSyncCount: number;
  isOnline: boolean;
  realtimeConnected: boolean;
  error?: string;
}

type SyncTable = 'body_metrics' | 'user_profiles' | 'daily_metrics';

type SyncableRecord = BodyMetrics | UserProfile | DailyMetrics | Record<string, unknown>;

interface QueuedChange {
  id: string;
  table: SyncTable;
  operation: 'INSERT' | 'UPDATE' | 'DELETE';
  data: SyncableRecord;
  timestamp: Date;
  retryCount: number;
}

export class RealtimeSyncManager {
  private static instance: RealtimeSyncManager;

  private state: SyncState = {
    isSyncing: false,
    lastSyncDate: null,
    syncStatus: 'idle',
    pendingSyncCount: 0,
    isOnline: typeof navigator !== 'undefined' ? navigator.onLine : true,
    realtimeConnected: false,
  };

  private listeners: Set<(state: SyncState) => void> = new Set();
  private syncInterval: NodeJS.Timeout | null = null;
  private realtimeChannel: RealtimeChannel | null = null;
  private conflictResolver = new ConflictResolver();
  private syncQueue: QueuedChange[] = [];
  private processingQueue = false;
  private supabase = createClient();
  private userId: string | null = null;

  // Debounce timers for batch operations
  private syncDebounceTimer: NodeJS.Timeout | null = null;
  private batchSyncDelay = 500; // ms

  // Retry configuration
  private maxRetries = 3;
  private retryDelay = 1000; // ms, exponential backoff

  private constructor() {
    if (typeof window !== 'undefined') {
      this.initialize();
    }
  }

  static getInstance(): RealtimeSyncManager {
    if (!RealtimeSyncManager.instance) {
      RealtimeSyncManager.instance = new RealtimeSyncManager();
    }
    return RealtimeSyncManager.instance;
  }

  private async initialize() {
    // Setup network monitoring
    window.addEventListener('online', this.handleOnline);
    window.addEventListener('offline', this.handleOffline);

    // Start periodic sync for missed updates
    this.startPeriodicSync();

    // Initialize pending count
    await this.updatePendingCount();

    // Setup realtime subscriptions
    await this.setupRealtimeSubscriptions();
  }

  async setUserId(userId: string) {
    if (this.userId !== userId) {
      this.userId = userId;
      await this.reconnectRealtime();
    }
  }

  private async setupRealtimeSubscriptions() {
    if (!this.userId || !this.state.isOnline) return;

    try {
      // Cleanup existing channel
      if (this.realtimeChannel) {
        await this.supabase.removeChannel(this.realtimeChannel);
      }

      // Create new channel for user-specific data
      this.realtimeChannel = this.supabase.channel(`sync:${this.userId}`)
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'body_metrics',
            filter: `user_id=eq.${this.userId}`,
          },
          (payload) => this.handleRealtimeChange('body_metrics', payload)
        )
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'user_profiles',
            filter: `id=eq.${this.userId}`,
          },
          (payload) => this.handleRealtimeChange('user_profiles', payload)
        )
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'daily_metrics',
            filter: `user_id=eq.${this.userId}`,
          },
          (payload) => this.handleRealtimeChange('daily_metrics', payload)
        )
        .subscribe((status) => {
          this.updateState({ realtimeConnected: status === 'SUBSCRIBED' });
          if (status === 'SUBSCRIBED') {
            console.log('Realtime subscriptions active');
          }
        });
    } catch (error) {
      console.error('Failed to setup realtime subscriptions:', error);
      this.updateState({ realtimeConnected: false });
    }
  }

  private async handleRealtimeChange(
    table: SyncTable,
    payload: RealtimePostgresChangesPayload<Record<string, unknown>>
  ) {
    // Skip if this change originated from our own sync
    // TODO: Add sync_id tracking to prevent echo
    // const syncId = payload.new?.sync_id || payload.old?.sync_id;
    // if (syncId === this.getSyncId()) return;

    try {
      switch (payload.eventType) {
        case 'INSERT':
          await this.handleRealtimeInsert(table, payload.new);
          break;
        case 'UPDATE':
          await this.handleRealtimeUpdate(table, payload.new, payload.old);
          break;
        case 'DELETE':
          await this.handleRealtimeDelete(table, payload.old);
          break;
      }
    } catch (error) {
      console.error(`Failed to handle realtime ${payload.eventType} for ${table}:`, error);
    }
  }

  private async handleRealtimeInsert(table: SyncTable, data: SyncableRecord) {
    if (!data) return;

    switch (table) {
      case 'body_metrics':
        await indexedDB.saveBodyMetrics({ ...(data as BodyMetrics), sync_status: 'synced' }, this.userId!);
        break;
      case 'user_profiles':
        await indexedDB.saveProfile({ ...(data as UserProfile), sync_status: 'synced' });
        break;
      case 'daily_metrics':
        await indexedDB.saveDailyMetrics({ ...(data as DailyMetrics), sync_status: 'synced' });
        break;
    }

    this.notifyListeners();
  }

  private async handleRealtimeUpdate(table: SyncTable, newData: SyncableRecord, _oldData: SyncableRecord | null) {
    if (!newData) return;

    // Check for conflicts with local unsynced changes
    const id = (newData as { id?: string | number }).id;
    const localData = id != null ? await this.getLocalRecord(table, String(id)) : null;

    const localSyncStatus = localData && (localData as { sync_status?: 'pending' | 'synced' | 'error' }).sync_status;

    if (localData && localSyncStatus === 'pending') {
      // We have a conflict - resolve it based on table type
      switch (table) {
        case 'body_metrics': {
          const resolved = this.conflictResolver.resolveBodyMetrics({
            local: localData as BodyMetrics,
            remote: newData as BodyMetrics,
          });
          await indexedDB.saveBodyMetrics({ ...resolved, sync_status: 'synced' }, this.userId!);
          break;
        }
        case 'user_profiles': {
          const resolved = this.conflictResolver.resolveProfile({
            local: localData as UserProfile,
            remote: newData as UserProfile,
          });
          await indexedDB.saveProfile({ ...resolved, sync_status: 'synced' });
          break;
        }
        case 'daily_metrics': {
          const resolved = this.conflictResolver.resolveDailyMetrics({
            local: localData as DailyMetrics,
            remote: newData as DailyMetrics,
          });
          await indexedDB.saveDailyMetrics({ ...resolved, sync_status: 'synced' });
          break;
        }
      }
    } else {
      // No conflict, apply the update
      await this.handleRealtimeInsert(table, newData);
    }
  }

  private async handleRealtimeDelete(table: SyncTable, data: Record<string, unknown>) {
    if (!data?.id) return;

    switch (table) {
      case 'body_metrics':
        // Mark as deleted for soft delete
        const metrics = await indexedDB.getBodyMetrics(this.userId!, undefined, undefined);
        const toDelete = metrics.find(m => m.id === data.id);
        if (toDelete) {
          await indexedDB.saveBodyMetrics({ ...toDelete, is_deleted: true }, this.userId!);
        }
        break;
      case 'daily_metrics':
        // Soft delete not implemented for daily metrics in IndexedDB
        // TODO: Implement soft delete for daily metrics
        break;
    }

    this.notifyListeners();
  }

  private async getLocalRecord(table: SyncTable, id: string): Promise<BodyMetrics | UserProfile | DailyMetrics | null> {
    switch (table) {
      case 'body_metrics':
        const metrics = await indexedDB.getBodyMetrics(this.userId!, undefined, undefined);
        return metrics.find(m => m.id === id) ?? null;
      case 'user_profiles':
        return await indexedDB.getProfile(this.userId!);
      case 'daily_metrics':
        // Daily metrics don't have a getAll method, need to fetch by date
        // TODO: Implement proper daily metrics fetching
        return null;
      default:
        return null;
    }
  }

  // Queue management for offline changes
  async queueChange(change: Omit<QueuedChange, 'id' | 'timestamp' | 'retryCount'>) {
    const queuedChange: QueuedChange = {
      ...change,
      id: crypto.randomUUID(),
      timestamp: new Date(),
      retryCount: 0,
    };

    this.syncQueue.push(queuedChange);
    await this.saveQueueToStorage();

    // Try to process immediately if online
    if (this.state.isOnline) {
      this.debouncedProcessQueue();
    }
  }

  private debouncedProcessQueue() {
    if (this.syncDebounceTimer) {
      clearTimeout(this.syncDebounceTimer);
    }

    this.syncDebounceTimer = setTimeout(() => {
      this.processQueue();
    }, this.batchSyncDelay);
  }

  private async processQueue() {
    if (this.processingQueue || !this.state.isOnline || this.syncQueue.length === 0) {
      return;
    }

    this.processingQueue = true;
    this.updateState({ isSyncing: true, syncStatus: 'syncing' });

    const processedIds: string[] = [];

    for (const change of this.syncQueue) {
      try {
        await this.processQueuedChange(change);
        processedIds.push(change.id);
      } catch (error) {
        console.error(`Failed to process queued change:`, error);

        change.retryCount++;
        if (change.retryCount >= this.maxRetries) {
          // Move to failed queue or notify user
          processedIds.push(change.id);
          this.updateState({
            error: `Failed to sync ${change.table} after ${this.maxRetries} attempts`
          });
        } else {
          // Exponential backoff for retry
          await new Promise(resolve =>
            setTimeout(resolve, this.retryDelay * Math.pow(2, change.retryCount))
          );
        }
      }
    }

    // Remove processed items
    this.syncQueue = this.syncQueue.filter(item => !processedIds.includes(item.id));
    await this.saveQueueToStorage();

    this.processingQueue = false;
    await this.updatePendingCount();

    this.updateState({
      isSyncing: false,
      syncStatus: this.syncQueue.length === 0 ? 'success' : 'error',
      lastSyncDate: new Date()
    });
  }

  private async processQueuedChange(change: QueuedChange) {
    const { table, operation, data } = change;

    // Add sync ID to prevent echo
    const syncData = { ...data, sync_id: this.getSyncId() };

    switch (operation) {
      case 'INSERT':
        await this.supabase.from(table).insert(syncData);
        break;
      case 'UPDATE':
        await this.supabase.from(table).update(syncData).eq('id', data.id);
        break;
      case 'DELETE':
        await this.supabase.from(table).delete().eq('id', data.id);
        break;
    }
  }

  // Sync methods
  async syncAll() {
    if (this.state.isSyncing || !this.state.isOnline) return;

    try {
      this.updateState({ isSyncing: true, syncStatus: 'syncing' });

      // Process any queued changes first
      await this.processQueue();

      // Then sync any unsynced local data
      const unsynced = await indexedDB.getUnsyncedItems();

      // Sync profiles
      for (const profile of unsynced.profiles) {
        await this.syncProfile(profile);
      }

      // Sync body metrics
      for (const metric of unsynced.bodyMetrics) {
        await this.syncBodyMetric(metric);
      }

      // Sync daily metrics
      for (const metric of unsynced.dailyMetrics) {
        await this.syncDailyMetric(metric);
      }

      // Pull latest data from server
      await this.pullLatestData();

      this.updateState({
        syncStatus: 'success',
        lastSyncDate: new Date(),
        error: undefined
      });
    } catch (error) {
      console.error('Sync failed:', error);
      this.updateState({
        syncStatus: 'error',
        error: error instanceof Error ? error.message : 'Sync failed'
      });
    } finally {
      this.updateState({ isSyncing: false });
      await this.updatePendingCount();
    }
  }

  private async syncProfile(profile: UserProfile) {
    const { data, error } = await this.supabase
      .from('user_profiles')
      .upsert({
        ...profile,
        sync_id: this.getSyncId(),
      })
      .select()
      .single();

    if (!error && data) {
      await indexedDB.saveProfile({ ...data, sync_status: 'synced' });
    }
  }

  private async syncBodyMetric(metric: BodyMetrics) {
    const { data, error } = await this.supabase
      .from('body_metrics')
      .upsert({
        ...metric,
        sync_id: this.getSyncId(),
      })
      .select()
      .single();

    if (!error && data) {
      await indexedDB.saveBodyMetrics({ ...data, sync_status: 'synced' }, this.userId!);
    }
  }

  private async syncDailyMetric(metric: DailyMetrics) {
    const { data, error } = await this.supabase
      .from('daily_metrics')
      .upsert({
        ...metric,
        sync_id: this.getSyncId(),
      })
      .select()
      .single();

    if (!error && data) {
      await indexedDB.saveDailyMetrics({ ...data, sync_status: 'synced' });
    }
  }

  private async pullLatestData() {
    if (!this.userId) return;

    // Get latest data from server
    const [profileResult, metricsResult, dailyResult] = await Promise.all([
      this.supabase
        .from('user_profiles')
        .select('*')
        .eq('id', this.userId)
        .single(),
      this.supabase
        .from('body_metrics')
        .select('*')
        .eq('user_id', this.userId)
        .order('created_at', { ascending: false })
        .limit(100),
      this.supabase
        .from('daily_metrics')
        .select('*')
        .eq('user_id', this.userId)
        .order('date', { ascending: false })
        .limit(30),
    ]);

    // Update local data
    if (profileResult.data) {
      await indexedDB.saveProfile({ ...profileResult.data, sync_status: 'synced' });
    }

    if (metricsResult.data) {
      for (const metric of metricsResult.data) {
        await indexedDB.saveBodyMetrics({ ...metric, sync_status: 'synced' }, this.userId!);
      }
    }

    if (dailyResult.data) {
      for (const metric of dailyResult.data) {
        await indexedDB.saveDailyMetrics({ ...metric, sync_status: 'synced' });
      }
    }
  }

  // Helper methods
  private getSyncId(): string {
    return `client-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  private async updatePendingCount() {
    const unsynced = await indexedDB.getUnsyncedItems();
    const pendingCount =
      unsynced.bodyMetrics.length +
      unsynced.dailyMetrics.length +
      unsynced.profiles.length +
      this.syncQueue.length;

    this.updateState({ pendingSyncCount: pendingCount });
  }

  private async saveQueueToStorage() {
    if (typeof window !== 'undefined' && window.localStorage) {
      localStorage.setItem('syncQueue', JSON.stringify(this.syncQueue));
    }
  }

  private async loadQueueFromStorage() {
    if (typeof window !== 'undefined' && window.localStorage) {
      const saved = localStorage.getItem('syncQueue');
      if (saved) {
        this.syncQueue = JSON.parse(saved);
      }
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
    listener(this.state);

    return () => {
      this.listeners.delete(listener);
    };
  }

  // Network handlers
  private handleOnline = async () => {
    this.updateState({ isOnline: true, syncStatus: 'idle' });
    await this.loadQueueFromStorage();
    await this.reconnectRealtime();
    this.syncAll();
  };

  private handleOffline = () => {
    this.updateState({ isOnline: false, syncStatus: 'offline', realtimeConnected: false });
    if (this.realtimeChannel) {
      this.supabase.removeChannel(this.realtimeChannel);
      this.realtimeChannel = null;
    }
  };

  private async reconnectRealtime() {
    if (this.state.isOnline && this.userId) {
      await this.setupRealtimeSubscriptions();
    }
  }

  // Periodic sync for reliability
  private startPeriodicSync() {
    // Sync every 5 minutes as a fallback
    this.syncInterval = setInterval(() => {
      if (this.state.isOnline) {
        this.syncAll();
      }
    }, 5 * 60 * 1000);
  }

  // Cleanup
  destroy() {
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
    }

    if (this.syncDebounceTimer) {
      clearTimeout(this.syncDebounceTimer);
    }

    if (this.realtimeChannel) {
      this.supabase.removeChannel(this.realtimeChannel);
    }

    window.removeEventListener('online', this.handleOnline);
    window.removeEventListener('offline', this.handleOffline);

    this.listeners.clear();
  }
}

// Export singleton instance
export const realtimeSyncManager = RealtimeSyncManager.getInstance();
