import { useEffect, useState, useCallback } from 'react';
import { realtimeSyncManager, type SyncStatus } from '@/lib/sync/realtime-sync-manager';
import { useAuth } from '@/contexts/ClerkAuthContext';

interface RealtimeSyncState {
  isSyncing: boolean;
  lastSyncDate: Date | null;
  syncStatus: SyncStatus;
  pendingSyncCount: number;
  isOnline: boolean;
  realtimeConnected: boolean;
  error?: string;
}

interface UseRealtimeSyncReturn extends RealtimeSyncState {
  syncNow: () => Promise<void>;
  clearError: () => void;
}

export function useRealtimeSync(): UseRealtimeSyncReturn {
  const { user } = useAuth();
  const [state, setState] = useState<RealtimeSyncState>({
    isSyncing: false,
    lastSyncDate: null,
    syncStatus: 'idle',
    pendingSyncCount: 0,
    isOnline: true,
    realtimeConnected: false,
  });

  useEffect(() => {
    // Set user ID when authenticated
    if (user?.id) {
      realtimeSyncManager.setUserId(user.id);
    }

    // Subscribe to sync state changes
    const unsubscribe = realtimeSyncManager.subscribe((syncState) => {
      setState(syncState);
    });

    return () => {
      unsubscribe();
    };
  }, [user?.id]);

  const syncNow = useCallback(async () => {
    try {
      await realtimeSyncManager.syncAll();
    } catch (error) {
      console.error('Manual sync failed:', error);
    }
  }, []);

  const clearError = useCallback(() => {
    setState(prev => ({ ...prev, error: undefined }));
  }, []);

  return {
    ...state,
    syncNow,
    clearError,
  };
}

// Hook for components that need to track specific data changes
export function useRealtimeData<T>(
  dataFetcher: () => Promise<T>
) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const { realtimeConnected } = useRealtimeSync();

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      const result = await dataFetcher();
      setData(result);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err : new Error('Failed to fetch data'));
    } finally {
      setLoading(false);
    }
  }, [dataFetcher]);

  useEffect(() => {
    fetchData();
  }, [fetchData, realtimeConnected]);

  // Subscribe to realtime updates
  useEffect(() => {
    if (!realtimeConnected) return;

    const unsubscribe = realtimeSyncManager.subscribe(() => {
      // Refetch data when sync state changes
      fetchData();
    });

    return unsubscribe;
  }, [realtimeConnected, fetchData]);

  return { data, loading, error, refetch: fetchData };
}
