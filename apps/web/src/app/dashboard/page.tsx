'use client';

import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { useEffect, useState, Suspense, useMemo, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { Loader2, Plus, Settings, Upload, ChevronDown } from 'lucide-react';
import { BodyMetrics, UserProfile, ProgressPhoto } from '@/types/body-metrics';
import { convertWeight } from '@/utils/body-calculations';
import { useNetworkStatus } from '@/hooks/use-network-status';
import { getFilePathFromUrl } from '@/utils/storage-utils';
import { getProfile } from '@/lib/profile';
import { createClient } from '@/lib/supabase/client';
import {
  createTimelineData,
  getTimelineDisplayValues,
  TimelineEntry,
} from '@/utils/data-interpolation';
import { calculatePhase, PhaseResult } from '@/utils/phase-calculator';
import { getMetricsTrends } from '@/utils/trend-calculator';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { MobileNavbar } from '@/components/MobileNavbar';
import { SyncStatus } from '@/components/SyncStatus';
import { useSync } from '@/hooks/use-sync';
import { syncManager } from '@/lib/sync/sync-manager';
import { indexedDB } from '@/lib/db/indexed-db';
import { AvatarDisplay, ProfilePanel } from './DashboardPanels';

function isSupabasePhotosUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  return url.includes('/storage/v1/object') && url.includes('/photos/');
}

async function getSignedPhotoUrlIfNeeded(
  supabase: ReturnType<typeof createClient>,
  url: string | null,
): Promise<string | null> {
  if (!url) return url;
  if (!isSupabasePhotosUrl(url)) {
    return url;
  }

  const path = getFilePathFromUrl(url, 'photos');
  if (!path) {
    return url;
  }

  const { data: signedData, error: signedError } = await supabase.storage
    .from('photos')
    .createSignedUrl(path, 60 * 10);

  if (signedError || !signedData || !signedData.signedUrl) {
    console.error('Failed to create signed URL for dashboard photo', signedError);
    return url;
  }

  let signedUrl = signedData.signedUrl as string;

  if (!signedUrl.startsWith('http')) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    if (supabaseUrl) {
      const base = supabaseUrl.endsWith('/') ? supabaseUrl.slice(0, -1) : supabaseUrl;
      const pathPart = signedUrl.startsWith('/') ? signedUrl : `/${signedUrl}`;
      signedUrl = `${base}${pathPart}`;
    }
  }

  return signedUrl;
}

const TimelineSlider = dynamic(
  () => import('./components/TimelineSlider').then((mod) => ({ default: mod.TimelineSlider })),
  {
    loading: () => (
      <div className="bg-linear-card border-linear-border h-32 animate-pulse border-t p-4" />
    ),
  },
);

// Dashboard display components moved to DashboardPanels.tsx

export default function DashboardPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const isOnline = useNetworkStatus();
  const _syncState = useSync();
  const [activeTabIndex, setActiveTabIndex] = useState(0);
  const [selectedDateIndex, setSelectedDateIndex] = useState(-1);
  const [_latestMetrics, setLatestMetrics] = useState<BodyMetrics | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [metricsHistory, setMetricsHistory] = useState<BodyMetrics[]>([]);
  const [profileLoading, setProfileLoading] = useState(true);
  const [photosHistory, setPhotosHistory] = useState<ProgressPhoto[]>([]);
  const [timelineData, setTimelineData] = useState<TimelineEntry[]>([]);
  const [phaseData, setPhaseData] = useState<PhaseResult | null>(null);
  const [metricsTrends, setMetricsTrends] = useState<ReturnType<typeof getMetricsTrends>>({
    weight: { direction: 'unknown', percentage: 0, difference: 0 },
    bodyFat: { direction: 'unknown', percentage: 0, difference: 0 },
    leanMass: { direction: 'unknown', percentage: 0, difference: 0 },
    ffmi: { direction: 'unknown', percentage: 0, difference: 0 },
  });

  // Handle keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (timelineData.length === 0 || selectedDateIndex < 0) return;

      // Don't handle if user is typing in an input
      const target = e.target as HTMLElement;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;

      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        e.stopPropagation();
        setSelectedDateIndex((prev) => Math.max(0, prev - 1));
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        e.stopPropagation();
        setSelectedDateIndex((prev) => Math.min(timelineData.length - 1, prev + 1));
      }
    };

    // Use capture phase to intercept before other handlers
    window.addEventListener('keydown', handleKeyDown, true);
    return () => window.removeEventListener('keydown', handleKeyDown, true);
  }, [timelineData.length, selectedDateIndex]);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  // Load profile data
  useEffect(() => {
    if (user) {
      setProfileLoading(true);
      getProfile(user.id)
        .then((profileData) => {
          if (profileData) {
            setProfile(profileData);
            // Check if onboarding is needed
            if (!profileData.onboarding_completed) {
              router.push('/onboarding');
              return;
            }
          } else {
            // No profile exists, redirect to onboarding
            router.push('/onboarding');
            return;
          }
          setProfileLoading(false);
        })
        .catch((error) => {
          console.error('Error loading profile:', error);
          setProfileLoading(false);
        });

      // Load all data in parallel for better performance
      const loadAllData = async () => {
        // Load from local storage first
        const localMetrics = await indexedDB.getBodyMetrics(user.id);
        if (localMetrics.length > 0) {
          setLatestMetrics(localMetrics[localMetrics.length - 1]);
          setMetricsHistory(localMetrics);
        }

        // Batch all server queries to run in parallel
        const supabase = createClient();
        const [metricsResult, photosResult] = await Promise.all([
          supabase
            .from('body_metrics')
            .select('*')
            .eq('user_id', user.id)
            .order('date', { ascending: false }),
          supabase
            .from('progress_photos')
            .select('*')
            .eq('user_id', user.id)
            .order('date', { ascending: false }),
        ]);

        // Process metrics data
        if (metricsResult.error) {
          console.error('Error loading metrics:', metricsResult.error);
        } else if (metricsResult.data && metricsResult.data.length > 0) {
          const metricsWithUrls = await Promise.all(
            metricsResult.data.map(async (metric) => {
              if (!metric.photo_url) {
                return metric;
              }

              const signedUrl = await getSignedPhotoUrlIfNeeded(supabase, metric.photo_url);
              return {
                ...metric,
                photo_url: signedUrl ?? metric.photo_url,
              };
            }),
          );

          setLatestMetrics(metricsWithUrls[0]);
          setMetricsHistory(metricsWithUrls.slice().reverse()); // Reverse to have oldest first for timeline

          // Save to local storage
          metricsWithUrls.forEach((metric) => {
            indexedDB.saveBodyMetrics(metric, user.id);
          });
        }

        // Process photos data
        if (photosResult.error) {
          console.error('Error loading photos:', photosResult.error);
        } else if (photosResult.data) {
          const photosWithUrls = await Promise.all(
            photosResult.data.map(async (photo) => {
              const signedPhotoUrl = await getSignedPhotoUrlIfNeeded(supabase, photo.photo_url);
              const signedThumbUrl = await getSignedPhotoUrlIfNeeded(
                supabase,
                photo.thumbnail_url ?? null,
              );

              return {
                ...photo,
                photo_url: signedPhotoUrl ?? photo.photo_url,
                thumbnail_url: signedThumbUrl ?? photo.thumbnail_url,
              } as ProgressPhoto;
            }),
          );

          setPhotosHistory(photosWithUrls.slice().reverse()); // Reverse to have oldest first for timeline
        }

        // Trigger sync to ensure we have latest data
        syncManager.syncIfNeeded();
      };

      loadAllData();
    }
  }, [user, router]);

  // Create timeline data when metrics or photos change
  useEffect(() => {
    if (metricsHistory.length > 0 || photosHistory.length > 0) {
      const timeline = createTimelineData(metricsHistory, photosHistory, profile?.height);
      setTimelineData(timeline);

      // Set selected index to the most recent entry
      if (timeline.length > 0) {
        setSelectedDateIndex(timeline.length - 1);
      }
    }
  }, [metricsHistory, photosHistory, profile?.height]);

  // Calculate phase data when metrics history changes
  useEffect(() => {
    if (metricsHistory.length > 0) {
      const phase = calculatePhase(metricsHistory, profile?.settings?.units?.weight || 'lbs');
      setPhaseData(phase);
    }
  }, [metricsHistory, profile?.settings?.units?.weight]);

  // Calculate trends when selected date changes
  useEffect(() => {
    if (selectedDateIndex >= 0 && timelineData.length > 0) {
      const currentData = timelineData[selectedDateIndex];

      // Find the previous entry with metrics data
      let previousIndex = selectedDateIndex - 1;
      let previousData = null;

      while (previousIndex >= 0) {
        const entry = timelineData[previousIndex];
        if (entry.metrics || entry.inferredData) {
          previousData = entry;
          break;
        }
        previousIndex--;
      }

      // Calculate trends
      const trends = getMetricsTrends(
        currentData.metrics ||
          (currentData.inferredData
            ? {
                ...currentData.inferredData,
                id: '',
                user_id: '',
                date: currentData.date,
                created_at: '',
                updated_at: '',
                body_fat_method: 'navy' as const,
                weight_unit: 'lbs' as const,
              }
            : null),
        previousData?.metrics ||
          (previousData?.inferredData
            ? {
                ...previousData.inferredData,
                id: '',
                user_id: '',
                date: previousData.date,
                created_at: '',
                updated_at: '',
                body_fat_method: 'navy' as const,
                weight_unit: 'lbs' as const,
              }
            : null),
      );

      setMetricsTrends(trends);
    }
  }, [selectedDateIndex, timelineData]);

  // Get current timeline entry based on selected date
  const currentEntry = useMemo(
    () =>
      selectedDateIndex >= 0 && selectedDateIndex < timelineData.length
        ? timelineData[selectedDateIndex]
        : null,
    [selectedDateIndex, timelineData],
  );

  const rawValues = useMemo(
    () => (currentEntry ? getTimelineDisplayValues(currentEntry) : null),
    [currentEntry],
  );

  // Convert weight from kg (database storage) to user's preferred unit
  const displayValues = useMemo(() => {
    if (!rawValues) return null;
    return {
      ...rawValues,
      weight:
        rawValues.weight && profile?.settings?.units?.weight === 'lbs'
          ? convertWeight(rawValues.weight, 'kg', 'lbs')
          : rawValues.weight,
    };
  }, [rawValues, profile?.settings?.units?.weight]);

  // Format helpers
  const _getFormattedWeight = useCallback(
    (weight?: number) => {
      if (!weight) return '--';
      return `${weight.toFixed(1)} ${profile?.settings?.units?.weight || 'lbs'}`;
    },
    [profile?.settings?.units?.weight],
  );

  const getFormattedHeight = useCallback(
    (height?: number) => {
      if (!height) return '--';

      const unit = profile?.settings?.units?.height || 'ft';

      if (unit === 'ft') {
        // Height is stored in inches when unit is 'ft'
        const feet = Math.floor(height / 12);
        const inches = height % 12;
        return `${feet}'${inches}"`;
      } else {
        // Height is in cm
        return `${height} cm`;
      }
    },
    [profile?.settings?.units?.height],
  );

  // Get photo URL for current entry
  const currentPhotoUrl = useMemo(() => {
    if (currentEntry?.photo?.photo_url) {
      return currentEntry.photo.photo_url;
    }
    if (currentEntry?.metrics?.photo_url) {
      return currentEntry.metrics.photo_url;
    }
    return undefined;
  }, [currentEntry]);

  if (loading || profileLoading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" aria-label="Loading" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="bg-linear-bg text-linear-text flex h-screen flex-col overflow-hidden">
      {/* Header - Desktop only */}
      <div className="border-linear-border hidden items-center justify-between border-b px-6 py-4 md:flex">
        <div className="flex items-center gap-3">
          <h1 className="text-linear-text text-xl font-semibold tracking-tight">LogYourBody</h1>
          {!isOnline && (
            <Badge variant="outline" className="border-yellow-500/50 text-xs text-yellow-500">
              Offline
            </Badge>
          )}
          <SyncStatus />
        </div>
        <div className="flex gap-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button className="bg-linear-purple hover:bg-linear-purple/90 font-medium text-white">
                <Plus className="mr-2 h-4 w-4" />
                Add Data
                <ChevronDown className="ml-2 h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem onClick={() => router.push('/log')}>
                <Plus className="mr-2 h-4 w-4" />
                Log Metrics
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => router.push('/import')}>
                <Upload className="mr-2 h-4 w-4" />
                Bulk Import
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button
            size="icon"
            variant="ghost"
            onClick={() => router.push('/settings')}
            className="text-linear-text-secondary hover:bg-linear-border/50 hover:text-linear-text h-10 w-10 transition-colors"
            title="Settings"
          >
            <Settings className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Main Content - Avatar/Photo Section with Profile Panel */}
      <div className="flex min-h-0 flex-1 flex-col md:flex-row">
        {/* Avatar/Photo Section with Tabs - 2/3 on desktop */}
        <div className="relative min-h-0 flex-[1.5] md:w-2/3 md:flex-1">
          <Tabs
            value={activeTabIndex.toString()}
            onValueChange={(v) => setActiveTabIndex(parseInt(v))}
            className="flex h-full flex-col"
            orientation="horizontal"
          >
            <TabsList
              className="bg-linear-card border-linear-border grid w-full grid-cols-2 rounded-none border-b"
              onKeyDown={(e) => {
                // Disable arrow key navigation for tabs
                if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                  e.preventDefault();
                  e.stopPropagation();
                }
              }}
            >
              <TabsTrigger value="0" className="data-[state=active]:bg-linear-border/50">
                Body Model
              </TabsTrigger>
              <TabsTrigger value="1" className="data-[state=active]:bg-linear-border/50">
                Photo
              </TabsTrigger>
            </TabsList>

            <TabsContent value="0" className="m-0 flex-1">
              <Suspense
                fallback={
                  <div className="bg-linear-bg flex h-full items-center justify-center">
                    <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
                  </div>
                }
              >
                <AvatarDisplay
                  gender={profile?.gender}
                  bodyFatPercentage={displayValues?.bodyFatPercentage}
                  showPhoto={false}
                  className="h-full w-full"
                  onAddPhoto={() => router.push('/log')}
                />
              </Suspense>
            </TabsContent>

            <TabsContent value="1" className="m-0 flex-1">
              <Suspense
                fallback={
                  <div className="bg-linear-bg flex h-full items-center justify-center">
                    <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
                  </div>
                }
              >
                <AvatarDisplay
                  gender={profile?.gender}
                  bodyFatPercentage={displayValues?.bodyFatPercentage}
                  showPhoto={true}
                  profileImage={currentPhotoUrl}
                  className="h-full w-full"
                  onAddPhoto={() => router.push('/log')}
                />
              </Suspense>
            </TabsContent>
          </Tabs>
        </div>

        {/* Profile Panel - 1/3 on desktop */}
        <div className="border-linear-border min-h-0 flex-[0.8] md:w-1/3 md:flex-1 md:border-l">
          <ProfilePanel
            entry={currentEntry}
            user={profile}
            formattedHeight={getFormattedHeight(profile?.height)}
            phaseData={phaseData}
            trends={metricsTrends}
          />
        </div>
      </div>

      {/* Timeline Slider */}
      {timelineData.length > 0 && (
        <div className="flex-shrink-0">
          <TimelineSlider
            timeline={timelineData}
            selectedIndex={selectedDateIndex}
            onIndexChange={setSelectedDateIndex}
          />
        </div>
      )}

      {/* Mobile Navigation Bar */}
      <MobileNavbar />
    </div>
  );
}
