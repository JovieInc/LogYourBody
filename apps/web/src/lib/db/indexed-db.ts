import { openDB, IDBPDatabase } from 'idb';
import type { BodyMetrics, UserProfile } from '@/types/body-metrics';

const DB_NAME = 'LogYourBodyDB';
const DB_VERSION = 1;

export interface DailyMetrics {
  id: string;
  user_id: string;
  date: Date;
  steps?: number;
  notes?: string;
  created_at: Date;
  updated_at: Date;
  sync_status?: 'pending' | 'synced' | 'error';
  is_deleted?: boolean;
  last_modified?: Date;
}

export interface SyncMetadata {
  id: string;
  entity_name: string;
  entity_id: string;
  last_sync_attempt?: Date;
  last_sync_success?: Date;
  last_sync_error?: string;
  sync_retry_count: number;
}

interface CachedBodyMetrics extends BodyMetrics {
  sync_status?: 'pending' | 'synced' | 'error';
  is_deleted?: boolean;
  last_modified?: Date;
}

interface CachedProfile extends UserProfile {
  sync_status?: 'pending' | 'synced' | 'error';
  is_deleted?: boolean;
  last_modified?: Date;
}

class IndexedDBManager {
  private db: IDBPDatabase | null = null;

  async initDB() {
    if (this.db) return this.db;

    this.db = await openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        // Body Metrics Store
        if (!db.objectStoreNames.contains('bodyMetrics')) {
          const bodyMetricsStore = db.createObjectStore('bodyMetrics', { keyPath: 'id' });
          bodyMetricsStore.createIndex('user_id', 'user_id', { unique: false });
          bodyMetricsStore.createIndex('date', 'date', { unique: false });
          bodyMetricsStore.createIndex('sync_status', 'sync_status', { unique: false });
          bodyMetricsStore.createIndex('user_date', ['user_id', 'date'], { unique: false });
        }

        // Daily Metrics Store
        if (!db.objectStoreNames.contains('dailyMetrics')) {
          const dailyMetricsStore = db.createObjectStore('dailyMetrics', { keyPath: 'id' });
          dailyMetricsStore.createIndex('user_id', 'user_id', { unique: false });
          dailyMetricsStore.createIndex('date', 'date', { unique: false });
          dailyMetricsStore.createIndex('sync_status', 'sync_status', { unique: false });
          dailyMetricsStore.createIndex('user_date', ['user_id', 'date'], { unique: true });
        }

        // Profiles Store
        if (!db.objectStoreNames.contains('profiles')) {
          const profilesStore = db.createObjectStore('profiles', { keyPath: 'id' });
          profilesStore.createIndex('email', 'email', { unique: true });
          profilesStore.createIndex('sync_status', 'sync_status', { unique: false });
        }

        // Sync Metadata Store
        if (!db.objectStoreNames.contains('syncMetadata')) {
          const syncStore = db.createObjectStore('syncMetadata', { keyPath: 'id' });
          syncStore.createIndex('entity', ['entity_name', 'entity_id'], { unique: true });
        }
      },
    });

    return this.db;
  }

  // Body Metrics Operations
  async saveBodyMetrics(metrics: BodyMetrics, userId: string): Promise<void> {
    const db = await this.initDB();
    const tx = db.transaction('bodyMetrics', 'readwrite');
    const store = tx.objectStore('bodyMetrics');

    const cached: CachedBodyMetrics = {
      ...metrics,
      user_id: userId,
      sync_status: metrics.sync_status ?? 'pending',
      is_deleted: false,
      last_modified: new Date(),
    };

    await store.put(cached);
    await tx.done;
  }

  async getBodyMetrics(userId: string, from?: Date, to?: Date): Promise<BodyMetrics[]> {
    const db = await this.initDB();
    const tx = db.transaction('bodyMetrics', 'readonly');
    const store = tx.objectStore('bodyMetrics');
    const index = store.index('user_id');

    let metrics = await index.getAll(userId);

    // Filter by date range if provided
    if (from || to) {
      metrics = metrics.filter(m => {
        const date = new Date(m.date);
        if (from && date < from) return false;
        if (to && date > to) return false;
        return true;
      });
    }

    // Filter out deleted items
    return metrics.filter(m => !m.is_deleted);
  }

  // Daily Metrics Operations
  async saveDailyMetrics(metrics: DailyMetrics): Promise<void> {
    const db = await this.initDB();
    const tx = db.transaction('dailyMetrics', 'readwrite');
    const store = tx.objectStore('dailyMetrics');

    const cached: DailyMetrics = {
      ...metrics,
      sync_status: metrics.sync_status ?? 'pending',
      is_deleted: false,
      last_modified: new Date(),
    };

    await store.put(cached);
    await tx.done;
  }

  async getDailyMetrics(userId: string, date: Date): Promise<DailyMetrics | null> {
    const db = await this.initDB();
    const tx = db.transaction('dailyMetrics', 'readonly');
    const store = tx.objectStore('dailyMetrics');
    const index = store.index('user_date');

    const startOfDay = new Date(date);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(date);
    endOfDay.setHours(23, 59, 59, 999);

    // Search for entries matching user and date
    const allEntries = await index.getAll(userId);
    const result = allEntries.find(entry => {
      const entryDate = new Date(entry.date);
      return entryDate >= startOfDay && entryDate <= endOfDay;
    });
    return result && !result.is_deleted ? result : null;
  }

  // Profile Operations
  async saveProfile(profile: UserProfile): Promise<void> {
    const db = await this.initDB();
    const tx = db.transaction('profiles', 'readwrite');
    const store = tx.objectStore('profiles');

    const cached: CachedProfile = {
      ...profile,
      sync_status: profile.sync_status ?? 'pending',
      is_deleted: false,
      last_modified: new Date(),
    };

    await store.put(cached);
    await tx.done;
  }

  async getProfile(userId: string): Promise<UserProfile | null> {
    const db = await this.initDB();
    const tx = db.transaction('profiles', 'readonly');
    const store = tx.objectStore('profiles');
    
    const result = await store.get(userId);
    return result && !result.is_deleted ? result : null;
  }

  // Sync Operations
  async getUnsyncedItems() {
    const db = await this.initDB();
    
    const bodyMetricsTx = db.transaction('bodyMetrics', 'readonly');
    const bodyMetricsStore = bodyMetricsTx.objectStore('bodyMetrics');
    const bodyMetricsIndex = bodyMetricsStore.index('sync_status');
    const bodyMetrics = await bodyMetricsIndex.getAll('pending');

    const dailyMetricsTx = db.transaction('dailyMetrics', 'readonly');
    const dailyMetricsStore = dailyMetricsTx.objectStore('dailyMetrics');
    const dailyMetricsIndex = dailyMetricsStore.index('sync_status');
    const dailyMetrics = await dailyMetricsIndex.getAll('pending');

    const profilesTx = db.transaction('profiles', 'readonly');
    const profilesStore = profilesTx.objectStore('profiles');
    const profilesIndex = profilesStore.index('sync_status');
    const profiles = await profilesIndex.getAll('pending');

    return {
      bodyMetrics: bodyMetrics.filter(m => !m.is_deleted),
      dailyMetrics: dailyMetrics.filter(m => !m.is_deleted),
      profiles: profiles.filter(p => !p.is_deleted),
    };
  }

  async markAsSynced(storeName: string, id: string): Promise<void> {
    const db = await this.initDB();
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    
    const item = await store.get(id);
    if (item) {
      item.sync_status = 'synced';
      await store.put(item);
    }
    
    await tx.done;
  }

  async updateSyncStatus(entityName: string, entityId: string, status: string, error?: string): Promise<void> {
    const db = await this.initDB();
    const tx = db.transaction('syncMetadata', 'readwrite');
    const store = tx.objectStore('syncMetadata');
    const index = store.index('entity');
    
    let metadata = await index.get([entityName, entityId]);
    
    if (!metadata) {
      metadata = {
        id: `${entityName}_${entityId}`,
        entity_name: entityName,
        entity_id: entityId,
        sync_retry_count: 0,
      };
    }
    
    metadata.last_sync_attempt = new Date();
    
    if (status === 'synced') {
      metadata.last_sync_success = new Date();
      metadata.sync_retry_count = 0;
      metadata.last_sync_error = null;
    } else {
      metadata.sync_retry_count += 1;
      metadata.last_sync_error = error;
    }
    
    await store.put(metadata);
    await tx.done;
  }

  // Cleanup Operations
  async cleanupDeletedItems(olderThan: Date): Promise<void> {
    const db = await this.initDB();
    
    // Cleanup body metrics
    const bodyMetricsTx = db.transaction('bodyMetrics', 'readwrite');
    const bodyMetricsStore = bodyMetricsTx.objectStore('bodyMetrics');
    const bodyMetrics = await bodyMetricsStore.getAll();
    
    for (const item of bodyMetrics) {
      if (item.is_deleted && item.last_modified && item.last_modified < olderThan) {
        await bodyMetricsStore.delete(item.id);
      }
    }
    
    await bodyMetricsTx.done;
    
    // Similar cleanup for other stores...
  }

  // Clear all data (useful for logout)
  async clearAllData(): Promise<void> {
    const db = await this.initDB();
    
    const tx = db.transaction(['bodyMetrics', 'dailyMetrics', 'profiles', 'syncMetadata'], 'readwrite');
    
    await Promise.all([
      tx.objectStore('bodyMetrics').clear(),
      tx.objectStore('dailyMetrics').clear(),
      tx.objectStore('profiles').clear(),
      tx.objectStore('syncMetadata').clear(),
    ]);
    
    await tx.done;
  }
}

export const indexedDB = new IndexedDBManager();