import type { BodyMetrics, UserProfile, UserSettings } from '@/types/body-metrics';
import type { DailyMetrics } from '@/lib/db/indexed-db';

export type ConflictResolutionStrategy = 'last-write-wins' | 'server-wins' | 'client-wins' | 'merge';

interface ConflictData<T> {
  local: T;
  remote: T;
  base?: T; // Original version if available
}

export class ConflictResolver {
  private strategy: ConflictResolutionStrategy;

  constructor(strategy: ConflictResolutionStrategy = 'last-write-wins') {
    this.strategy = strategy;
  }

  resolveBodyMetrics(conflict: ConflictData<BodyMetrics>): BodyMetrics {
    switch (this.strategy) {
      case 'last-write-wins':
        return this.resolveByTimestamp(conflict.local, conflict.remote);
      
      case 'server-wins':
        return conflict.remote;
      
      case 'client-wins':
        return conflict.local;
      
      case 'merge':
        return this.mergeBodyMetrics(conflict);
      
      default:
        return this.resolveByTimestamp(conflict.local, conflict.remote);
    }
  }

  resolveDailyMetrics(conflict: ConflictData<DailyMetrics>): DailyMetrics {
    switch (this.strategy) {
      case 'last-write-wins':
        return this.resolveByTimestamp(conflict.local, conflict.remote);
      
      case 'server-wins':
        return conflict.remote;
      
      case 'client-wins':
        return conflict.local;
      
      case 'merge':
        return this.mergeDailyMetrics(conflict);
      
      default:
        return this.resolveByTimestamp(conflict.local, conflict.remote);
    }
  }

  resolveProfile(conflict: ConflictData<UserProfile>): UserProfile {
    switch (this.strategy) {
      case 'last-write-wins':
        return this.resolveByTimestamp(conflict.local, conflict.remote);
      
      case 'server-wins':
        return conflict.remote;
      
      case 'client-wins':
        return conflict.local;
      
      case 'merge':
        return this.mergeProfiles(conflict);
      
      default:
        return this.resolveByTimestamp(conflict.local, conflict.remote);
    }
  }

  private resolveByTimestamp<T extends { updated_at: string | Date }>(local: T, remote: T): T {
    const localTime = new Date(local.updated_at).getTime();
    const remoteTime = new Date(remote.updated_at).getTime();
    
    return localTime > remoteTime ? local : remote;
  }

  private mergeBodyMetrics(conflict: ConflictData<BodyMetrics>): BodyMetrics {
    const { local, remote } = conflict;
    
    // Use most recent timestamp
    const useLocal = this.resolveByTimestamp(local, remote) === local;
    const base = useLocal ? local : remote;
    const other = useLocal ? remote : local;
    
    // Merge strategy: Take base values but preserve any additional data from other
    return {
      ...base,
      // Preserve photo URL if only one has it
      photo_url: base.photo_url || other.photo_url,
      // Merge notes if different
      notes: this.mergeNotes(base.notes, other.notes),
      // Use most complete body composition data
      body_fat_percentage: base.body_fat_percentage ?? other.body_fat_percentage,
      body_fat_method: base.body_fat_method || other.body_fat_method,
      // Preserve all measurements
      waist: base.waist ?? other.waist,
      neck: base.neck ?? other.neck,
      hip: base.hip ?? other.hip,
      // Keep the latest updated timestamp
      updated_at: base.updated_at,
    };
  }

  private mergeDailyMetrics(conflict: ConflictData<DailyMetrics>): DailyMetrics {
    const { local, remote } = conflict;
    
    const useLocal = this.resolveByTimestamp(local, remote) === local;
    const base = useLocal ? local : remote;
    const other = useLocal ? remote : local;
    
    return {
      ...base,
      // Use maximum step count (assuming device might have missed some steps)
      steps: Math.max(base.steps || 0, other.steps || 0) || undefined,
      // Merge notes
      notes: this.mergeNotes(base.notes, other.notes),
      updated_at: base.updated_at,
    };
  }

  private mergeProfiles(conflict: ConflictData<UserProfile>): UserProfile {
    const { local, remote } = conflict;
    
    const useLocal = this.resolveByTimestamp(local, remote) === local;
    const base = useLocal ? local : remote;
    const other = useLocal ? remote : local;
    
    return {
      ...base,
      // Preserve any fields that are only set in one version
      username: base.username || other.username,
      full_name: base.full_name || other.full_name,
      avatar_url: base.avatar_url || other.avatar_url,
      bio: base.bio || other.bio,
      // Use most recent profile updates
      height: base.height ?? other.height,
      height_unit: base.height_unit || other.height_unit,
      goal_weight: base.goal_weight ?? other.goal_weight,
      goal_weight_unit: base.goal_weight_unit || other.goal_weight_unit,
      // Merge settings if both exist
      settings: this.mergeSettings(base.settings, other.settings),
      updated_at: base.updated_at,
    };
  }

  private mergeNotes(note1?: string, note2?: string): string | undefined {
    if (!note1) return note2;
    if (!note2) return note1;
    if (note1 === note2) return note1;
    
    // Combine notes with separator
    return `${note1}\n---\n${note2}`;
  }

  private mergeSettings(settings1?: UserSettings, settings2?: UserSettings): UserSettings | undefined {
    if (!settings1) return settings2;
    if (!settings2) return settings1;
    
    // Deep merge settings objects
    return {
      ...settings2,
      ...settings1,
      // Merge nested objects
      units: {
        ...settings2?.units,
        ...settings1?.units,
      },
      notifications: {
        ...settings2?.notifications,
        ...settings1?.notifications,
      },
    };
  }

  // Check if two records have conflicting changes
  static hasConflict<T extends { updated_at: string | Date }>(
    local: T,
    remote: T,
    lastSyncTime?: Date
  ): boolean {
    const localTime = new Date(local.updated_at).getTime();
    const remoteTime = new Date(remote.updated_at).getTime();
    
    // If we have a last sync time, check if both were modified after sync
    if (lastSyncTime) {
      const syncTime = lastSyncTime.getTime();
      return localTime > syncTime && remoteTime > syncTime;
    }
    
    // Otherwise, consider it a conflict if timestamps differ significantly (> 1 second)
    return Math.abs(localTime - remoteTime) > 1000;
  }
}

export const conflictResolver = new ConflictResolver('last-write-wins');
