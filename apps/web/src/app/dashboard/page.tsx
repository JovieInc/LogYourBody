'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect, useState, Suspense, useMemo, useCallback } from 'react'
import dynamic from 'next/dynamic'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Progress } from '@/components/ui/progress'
import { Badge } from '@/components/ui/badge'
import {
  Loader2,
  User,
  Camera,
  Plus,
  Settings,
  Upload,
  ChevronDown
} from 'lucide-react'
import { BodyMetrics, UserProfile, ProgressPhoto } from '@/types/body-metrics'
import { calculateFFMI, getBodyFatCategory, convertWeight } from '@/utils/body-calculations'
import { getAvatarUrl } from '@/utils/avatar-utils'
import { cn } from '@/lib/utils'
import Image from 'next/image'
import { useNetworkStatus } from '@/hooks/use-network-status'
import { ensurePublicUrl } from '@/utils/storage-utils'
import { getProfile } from '@/lib/supabase/profile'
import { createClient } from '@/lib/supabase/client'
import { createTimelineData, getTimelineDisplayValues, TimelineEntry } from '@/utils/data-interpolation'
import { Info } from 'lucide-react'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import { BodyFatScale } from '@/components/BodyFatScale'
import { calculatePhase, PhaseResult } from '@/utils/phase-calculator'
import { getMetricsTrends, getTrendArrow, getTrendColorClass } from '@/utils/trend-calculator'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { MobileNavbar } from '@/components/MobileNavbar'
import { SyncStatus } from '@/components/SyncStatus'
import { useSync } from '@/hooks/use-sync'
import { syncManager } from '@/lib/sync/sync-manager'
import { indexedDB } from '@/lib/db/indexed-db'

// Lazy load heavy components for better performance
const PhaseIndicator = dynamic(() => import('./components/PhaseIndicator').then(mod => ({ default: mod.PhaseIndicator })), {
  loading: () => <div className="bg-linear-bg rounded-lg p-4 border border-linear-border h-24 animate-pulse" />
})

const TimelineSlider = dynamic(() => import('./components/TimelineSlider').then(mod => ({ default: mod.TimelineSlider })), {
  loading: () => <div className="bg-linear-card border-t border-linear-border p-4 h-32 animate-pulse" />
})

// Components extracted to separate files for better code splitting

// Avatar display component
const AvatarDisplay = ({
  gender,
  bodyFatPercentage,
  showPhoto,
  profileImage,
  className,
  onAddPhoto
}: {
  gender?: string
  bodyFatPercentage?: number
  showPhoto?: boolean
  profileImage?: string
  className?: string
  onAddPhoto?: () => void
}) => {
  const [imageError, setImageError] = useState(false)

  if (showPhoto) {
    if (profileImage) {
      return (
        <div className={cn("relative flex items-center justify-center bg-linear-bg", className)}>
          <Image
            src={profileImage}
            alt="Profile"
            fill
            className="object-cover"
          />
        </div>
      )
    } else {
      // No photo available - show add photo prompt
      return (
        <div className={cn("relative flex items-center justify-center bg-linear-bg", className)}>
          <div className="text-center">
            <Camera className="h-24 w-24 mx-auto mb-4 text-linear-text-tertiary" />
            <p className="text-linear-text-secondary mb-4">No photo yet</p>
            <Button
              variant="outline"
              className="border-linear-border"
              onClick={onAddPhoto}
            >
              <Plus className="h-4 w-4 mr-2" />
              Add Photo
            </Button>
          </div>
        </div>
      )
    }
  }

  const avatarUrl = getAvatarUrl(gender as 'male' | 'female', bodyFatPercentage)

  return (
    <div className={cn("relative flex items-center justify-center bg-linear-bg p-8", className)}>
      {avatarUrl && !imageError ? (
        <Image
          src={avatarUrl}
          alt={`Body silhouette at ${bodyFatPercentage || 20}% body fat`}
          width={300}
          height={400}
          className="h-full w-auto max-h-[500px] object-contain"
          onError={() => setImageError(true)}
        />
      ) : (
        <div className="text-center">
          <User className="h-24 w-24 mx-auto mb-4 text-linear-text-tertiary" />
          <p className="text-white mb-2">No body model yet</p>
          <p className="text-sm text-linear-text-secondary mb-4">Add your measurements to generate one</p>
          <Button
            variant="outline"
            size="sm"
            className="border-linear-purple text-linear-purple hover:bg-linear-purple/10"
            onClick={onAddPhoto}
          >
            Add Measurements
          </Button>
        </div>
      )}
    </div>
  )
}

// Profile Panel component
const ProfilePanel = ({
  entry,
  user,
  formattedHeight,
  phaseData,
  trends
}: {
  entry: TimelineEntry | null
  user: UserProfile | null
  formattedHeight: string
  phaseData: PhaseResult | null
  trends: ReturnType<typeof getMetricsTrends>
}) => {
  const rawValues = useMemo(() =>
    entry ? getTimelineDisplayValues(entry) : null,
    [entry]
  )

  const getDisplayName = () => {
    if (!user) return 'User'

    const fullName = (user.full_name || '').trim()
    if (fullName.length > 0) {
      return fullName.split(/\s+/)[0]
    }

    if (user.email) {
      return user.email.split('@')[0]
    }

    return 'User'
  }

  // Convert weight from kg (database storage) to user's preferred unit
  const displayValues = useMemo(() => {
    if (!rawValues) return null
    return {
      ...rawValues,
      weight: rawValues.weight && user?.settings?.units?.weight === 'lbs'
        ? convertWeight(rawValues.weight, 'kg', 'lbs')
        : rawValues.weight
    }
  }, [rawValues, user?.settings?.units?.weight])

  const bodyFatCategory = useMemo(() =>
    displayValues?.bodyFatPercentage && user?.gender
      ? getBodyFatCategory(displayValues.bodyFatPercentage, user.gender as 'male' | 'female')
      : null,
    [displayValues?.bodyFatPercentage, user?.gender]
  )

  // Calculate age from date of birth
  const age = useMemo(() => {
    if (!user?.date_of_birth) return null
    try {
      const birthDate = new Date(user.date_of_birth)
      const today = new Date()
      let age = today.getFullYear() - birthDate.getFullYear()
      const monthDiff = today.getMonth() - birthDate.getMonth()
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--
      }
      return age
    } catch {
      return null
    }
  }, [user?.date_of_birth])

  return (
    <div className="h-full overflow-y-auto bg-linear-card p-6">
      <div className="space-y-6">
        {/* User Info */}
        <div className="flex items-start justify-between">
          {/* Left side - Name and email */}
          <div>
            <h2 className="text-2xl font-bold text-linear-text mb-1">
              {getDisplayName()}
            </h2>
            <p className="text-sm text-linear-text-secondary">{user?.email}</p>
          </div>

          {/* Right side - Metrics */}
          <div className="text-right">
            <div className="text-sm text-linear-text-secondary">
              {[
                age && `${age}y`,
                user?.height && formattedHeight,
                user?.gender && (user.gender === 'male' ? 'Male' : 'Female')
              ].filter(Boolean).join(' • ')}
            </div>
          </div>
        </div>

        {/* Current Stats */}
        <div className="space-y-4">
          <h3 className="text-sm font-semibold text-linear-text uppercase tracking-wider">Current Stats</h3>

          {/* Stats Grid - Mobile optimized with horizontal scroll */}
          <div className="flex md:grid md:grid-cols-2 gap-3 overflow-x-auto md:overflow-visible -mx-6 px-6 md:mx-0 md:px-0 pb-2 md:pb-0">
            {/* Weight */}
            <div className="bg-linear-bg rounded-lg p-4 border border-linear-border min-w-[140px] md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="text-xs uppercase tracking-wider text-linear-text-secondary mb-2">Weight</div>
                <div className="flex items-baseline gap-1">
                  <span className="text-4xl md:text-3xl font-bold text-linear-text">
                    {displayValues?.weight?.toFixed(1) || '--'}
                  </span>
                  <span className="text-lg md:text-sm text-linear-text-secondary font-medium">
                    {user?.settings?.units?.weight || 'lbs'}
                  </span>
                </div>
                <div className="flex items-center gap-1 mt-2 h-6">
                  {trends.weight.direction !== 'unknown' && (
                    <span className={cn("text-sm font-medium", getTrendColorClass(trends.weight.direction, 'weight'))}>
                      {getTrendArrow(trends.weight.direction)}
                      {trends.weight.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.weight.difference > 0 ? '+' : ''}{trends.weight.difference.toFixed(1)} {user?.settings?.units?.weight || 'lbs'}
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Body Fat */}
            <div className="bg-linear-bg rounded-lg p-4 border border-linear-border min-w-[140px] md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="flex items-center gap-1 mb-2">
                  <span className="text-xs uppercase tracking-wider text-linear-text-secondary">Body Fat</span>
                  {displayValues?.isInferred && (
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger>
                          <Info className="h-3 w-3 text-linear-text-tertiary" />
                        </TooltipTrigger>
                        <TooltipContent>
                          <p className="text-xs">
                            Interpolated ({displayValues.confidenceLevel})
                          </p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  )}
                </div>
                <div className="flex items-baseline gap-0.5">
                  <span className="text-4xl md:text-3xl font-bold text-linear-text">
                    {displayValues?.bodyFatPercentage?.toFixed(1) || '--'}
                  </span>
                  <span className="text-2xl md:text-xl text-linear-text-secondary font-medium">%</span>
                </div>
                {bodyFatCategory && (
                  <div className="text-xs text-linear-text-tertiary mt-1">
                    {bodyFatCategory}
                  </div>
                )}
                <div className="flex items-center gap-1 mt-2 h-6">
                  {trends.bodyFat.direction !== 'unknown' && (
                    <span className={cn("text-sm font-medium", getTrendColorClass(trends.bodyFat.direction, 'bodyFat'))}>
                      {getTrendArrow(trends.bodyFat.direction)}
                      {trends.bodyFat.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.bodyFat.difference > 0 ? '+' : ''}{trends.bodyFat.percentage.toFixed(1)}%
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Lean Mass */}
            <div className="bg-linear-bg rounded-lg p-4 border border-linear-border min-w-[140px] md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="text-xs uppercase tracking-wider text-linear-text-secondary mb-2">Lean Mass</div>
                {displayValues?.weight && displayValues?.bodyFatPercentage ? (
                  <>
                    <div className="flex items-baseline gap-1">
                      <span className="text-4xl md:text-3xl font-bold text-linear-text">
                        {(displayValues.weight * (1 - displayValues.bodyFatPercentage / 100)).toFixed(1)}
                      </span>
                      <span className="text-lg md:text-sm text-linear-text-secondary font-medium">
                        {user?.settings?.units?.weight || 'lbs'}
                      </span>
                    </div>
                  </>
                ) : (
                  <div>
                    <span className="text-4xl md:text-3xl font-bold text-linear-text-tertiary">--</span>
                  </div>
                )}
                <div className="flex items-center gap-1 mt-2 h-6">
                  {trends.leanMass.direction !== 'unknown' && (
                    <span className={cn("text-sm font-medium", getTrendColorClass(trends.leanMass.direction, 'leanMass'))}>
                      {getTrendArrow(trends.leanMass.direction)}
                      {trends.leanMass.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.leanMass.difference > 0 ? '+' : ''}{trends.leanMass.difference.toFixed(1)} {user?.settings?.units?.weight || 'lbs'}
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* FFMI */}
            <div className="bg-linear-bg rounded-lg p-4 border border-linear-border min-w-[140px] md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="flex items-center gap-1 mb-2">
                  <span className="text-xs uppercase tracking-wider text-linear-text-secondary">FFMI</span>
                  {displayValues?.isInferred && displayValues?.weight && displayValues?.bodyFatPercentage && user?.height && (
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger>
                          <Info className="h-3 w-3 text-linear-text-tertiary" />
                        </TooltipTrigger>
                        <TooltipContent>
                          <p className="text-xs">
                            Calculated from interpolated values
                          </p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  )}
                </div>
                {displayValues?.weight && displayValues?.bodyFatPercentage && user?.height ? (
                  <>
                    <div>
                      <span className="text-4xl md:text-3xl font-bold text-linear-text">
                        {(() => {
                          // displayValues.weight is already in user's preferred unit
                          // rawValues.weight is in kg (database storage)
                          const weightInKg = rawValues?.weight || 0

                          const heightInCm = user?.settings?.units?.height === 'ft'
                            ? user.height * 2.54
                            : user.height

                          return calculateFFMI(weightInKg, heightInCm, displayValues.bodyFatPercentage).normalized_ffmi.toFixed(1)
                        })()}
                      </span>
                    </div>
                    <div className="text-xs text-linear-text-tertiary mt-1">
                      {(() => {
                        // displayValues.weight is already in user's preferred unit
                        // rawValues.weight is in kg (database storage)
                        const weightInKg = rawValues?.weight || 0

                        const heightInCm = user?.settings?.units?.height === 'ft'
                          ? user.height * 2.54
                          : user.height

                        const interpretation = calculateFFMI(weightInKg, heightInCm, displayValues.bodyFatPercentage).interpretation
                        // Convert snake_case to Title Case
                        return interpretation.split('_').map(word =>
                          word.charAt(0).toUpperCase() + word.slice(1)
                        ).join(' ')
                      })()}
                    </div>
                    <div className="flex items-center gap-1 mt-2 h-6">
                      {trends.ffmi.direction !== 'unknown' && (
                        <span className={cn("text-sm font-medium", getTrendColorClass(trends.ffmi.direction, 'ffmi'))}>
                          {getTrendArrow(trends.ffmi.direction)}
                          {trends.ffmi.direction !== 'stable' && (
                            <span className="ml-1">
                              {trends.ffmi.difference > 0 ? '+' : ''}{trends.ffmi.difference.toFixed(1)}
                            </span>
                          )}
                        </span>
                      )}
                    </div>
                  </>
                ) : (
                  <>
                    <div>
                      <span className="text-4xl md:text-3xl font-bold text-linear-text-tertiary">--</span>
                    </div>
                    <div className="text-xs text-linear-text-tertiary mt-1">Needs more data</div>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Phase Indicator */}
        <PhaseIndicator phaseData={phaseData} />

        {/* Goals Progress */}
        <div className="space-y-4">
          <h3 className="text-sm font-semibold text-linear-text uppercase tracking-wider">Goals Progress</h3>

          <div className="space-y-4">
            {/* FFMI Goal */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm text-linear-text">FFMI Goal</span>
                <span className="text-sm font-medium text-linear-text">
                  {displayValues?.weight && displayValues?.bodyFatPercentage && user?.height ? (
                    <>
                      {(() => {
                        // displayValues.weight is already in user's preferred unit
                        // rawValues.weight is in kg (database storage)
                        const weightInKg = rawValues?.weight || 0

                        const heightInCm = user?.settings?.units?.height === 'ft'
                          ? user.height * 2.54
                          : user.height

                        return calculateFFMI(weightInKg, heightInCm, displayValues.bodyFatPercentage).normalized_ffmi.toFixed(1)
                      })()} / 22
                    </>
                  ) : (
                    '-- / 22'
                  )}
                </span>
              </div>
              <Progress
                value={
                  displayValues?.weight && displayValues?.bodyFatPercentage && user?.height
                    ? (() => {
                      // displayValues.weight is already in user's preferred unit
                      // rawValues.weight is in kg (database storage)
                      const weightInKg = rawValues?.weight || 0

                      const heightInCm = user?.settings?.units?.height === 'ft'
                        ? user.height * 2.54
                        : user.height

                      const ffmi = calculateFFMI(weightInKg, heightInCm, displayValues.bodyFatPercentage)
                      return Math.min(100, (ffmi.normalized_ffmi / 22) * 100)
                    })()
                    : 0
                }
                className="h-2"
              />
            </div>

            {/* Body Fat Goal */}
            <div>
              <div className="mb-2">
                <span className="text-sm text-linear-text">Body Fat Goal</span>
              </div>
              <BodyFatScale
                currentBF={displayValues?.bodyFatPercentage}
                gender={user?.gender as 'male' | 'female' | undefined}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// TimelineSlider component moved to components/TimelineSlider.tsx

export default function DashboardPage() {
  const { user, loading } = useAuth()
  const router = useRouter()
  const isOnline = useNetworkStatus()
  const _syncState = useSync()
  const [activeTabIndex, setActiveTabIndex] = useState(0)
  const [selectedDateIndex, setSelectedDateIndex] = useState(-1)
  const [_latestMetrics, setLatestMetrics] = useState<BodyMetrics | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [metricsHistory, setMetricsHistory] = useState<BodyMetrics[]>([])
  const [profileLoading, setProfileLoading] = useState(true)
  const [photosHistory, setPhotosHistory] = useState<ProgressPhoto[]>([])
  const [timelineData, setTimelineData] = useState<TimelineEntry[]>([])
  const [phaseData, setPhaseData] = useState<PhaseResult | null>(null)
  const [metricsTrends, setMetricsTrends] = useState<ReturnType<typeof getMetricsTrends>>({
    weight: { direction: 'unknown', percentage: 0, difference: 0 },
    bodyFat: { direction: 'unknown', percentage: 0, difference: 0 },
    leanMass: { direction: 'unknown', percentage: 0, difference: 0 },
    ffmi: { direction: 'unknown', percentage: 0, difference: 0 }
  })

  // Handle keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (timelineData.length === 0 || selectedDateIndex < 0) return

      // Don't handle if user is typing in an input
      const target = e.target as HTMLElement
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return

      if (e.key === 'ArrowLeft') {
        e.preventDefault()
        e.stopPropagation()
        setSelectedDateIndex(prev => Math.max(0, prev - 1))
      } else if (e.key === 'ArrowRight') {
        e.preventDefault()
        e.stopPropagation()
        setSelectedDateIndex(prev => Math.min(timelineData.length - 1, prev + 1))
      }
    }

    // Use capture phase to intercept before other handlers
    window.addEventListener('keydown', handleKeyDown, true)
    return () => window.removeEventListener('keydown', handleKeyDown, true)
  }, [timelineData.length, selectedDateIndex])

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin')
    }
  }, [user, loading, router])

  // Load profile data
  useEffect(() => {
    if (user) {
      setProfileLoading(true)
      getProfile(user.id).then((profileData) => {
        if (profileData) {
          setProfile(profileData)
          // Check if onboarding is needed
          if (!profileData.onboarding_completed) {
            router.push('/onboarding')
            return
          }
        } else {
          // No profile exists, redirect to onboarding
          router.push('/onboarding')
          return
        }
        setProfileLoading(false)
      }).catch((error) => {
        console.error('Error loading profile:', error)
        setProfileLoading(false)
      })

      // Load all data in parallel for better performance
      const loadAllData = async () => {
        // Load from local storage first
        const localMetrics = await indexedDB.getBodyMetrics(user.id)
        if (localMetrics.length > 0) {
          setLatestMetrics(localMetrics[localMetrics.length - 1])
          setMetricsHistory(localMetrics)
        }

        // Batch all server queries to run in parallel
        const supabase = createClient()
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
            .order('date', { ascending: false })
        ])

        // Process metrics data
        if (metricsResult.error) {
          console.error('Error loading metrics:', metricsResult.error)
        } else if (metricsResult.data && metricsResult.data.length > 0) {
          setLatestMetrics(metricsResult.data[0])
          setMetricsHistory(metricsResult.data.reverse()) // Reverse to have oldest first for timeline

          // Save to local storage
          metricsResult.data.forEach(metric => {
            indexedDB.saveBodyMetrics(metric, user.id)
          })
        }

        // Process photos data
        if (photosResult.error) {
          console.error('Error loading photos:', photosResult.error)
        } else if (photosResult.data) {
          setPhotosHistory(photosResult.data.reverse()) // Reverse to have oldest first for timeline
        }

        // Trigger sync to ensure we have latest data
        syncManager.syncIfNeeded()
      }

      loadAllData()
    }
  }, [user, router])

  // Create timeline data when metrics or photos change
  useEffect(() => {
    if (metricsHistory.length > 0 || photosHistory.length > 0) {
      const timeline = createTimelineData(metricsHistory, photosHistory, profile?.height)
      setTimelineData(timeline)

      // Set selected index to the most recent entry
      if (timeline.length > 0) {
        setSelectedDateIndex(timeline.length - 1)
      }
    }
  }, [metricsHistory, photosHistory, profile?.height])

  // Calculate phase data when metrics history changes
  useEffect(() => {
    if (metricsHistory.length > 0) {
      const phase = calculatePhase(metricsHistory, profile?.settings?.units?.weight || 'lbs')
      setPhaseData(phase)
    }
  }, [metricsHistory, profile?.settings?.units?.weight])

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
        currentData.metrics || (currentData.inferredData ? {
          ...currentData.inferredData,
          id: '',
          user_id: '',
          date: currentData.date,
          created_at: '',
          updated_at: '',
          body_fat_method: 'navy' as const,
          weight_unit: 'lbs' as const
        } : null),
        previousData?.metrics || (previousData?.inferredData ? {
          ...previousData.inferredData,
          id: '',
          user_id: '',
          date: previousData.date,
          created_at: '',
          updated_at: '',
          body_fat_method: 'navy' as const,
          weight_unit: 'lbs' as const
        } : null)
      );

      setMetricsTrends(trends);
    }
  }, [selectedDateIndex, timelineData])

  // Get current timeline entry based on selected date
  const currentEntry = useMemo(() =>
    selectedDateIndex >= 0 && selectedDateIndex < timelineData.length
      ? timelineData[selectedDateIndex]
      : null,
    [selectedDateIndex, timelineData]
  )

  const rawValues = useMemo(() =>
    currentEntry ? getTimelineDisplayValues(currentEntry) : null,
    [currentEntry]
  )

  // Convert weight from kg (database storage) to user's preferred unit
  const displayValues = useMemo(() => {
    if (!rawValues) return null
    return {
      ...rawValues,
      weight: rawValues.weight && profile?.settings?.units?.weight === 'lbs'
        ? convertWeight(rawValues.weight, 'kg', 'lbs')
        : rawValues.weight
    }
  }, [rawValues, profile?.settings?.units?.weight])

  // Format helpers
  const _getFormattedWeight = useCallback((weight?: number) => {
    if (!weight) return '--'
    return `${weight.toFixed(1)} ${profile?.settings?.units?.weight || 'lbs'}`
  }, [profile?.settings?.units?.weight])

  const getFormattedHeight = useCallback((height?: number) => {
    if (!height) return '--'

    const unit = profile?.settings?.units?.height || 'ft'

    if (unit === 'ft') {
      // Height is stored in inches when unit is 'ft'
      const feet = Math.floor(height / 12)
      const inches = height % 12
      return `${feet}'${inches}"`
    } else {
      // Height is in cm
      return `${height} cm`
    }
  }, [profile?.settings?.units?.height])

  // Get photo URL for current entry
  const currentPhotoUrl = useMemo(() => {
    if (currentEntry?.photo?.photo_url) {
      return ensurePublicUrl(currentEntry.photo.photo_url)
    }
    if (currentEntry?.metrics?.photo_url) {
      return ensurePublicUrl(currentEntry.metrics.photo_url)
    }
    return undefined
  }, [currentEntry])

  if (loading || profileLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-linear-bg">
        <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" aria-label="Loading" />
      </div>
    )
  }

  if (!user) {
    return null
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-linear-bg text-linear-text">
      {/* Header - Desktop only */}
      <div className="hidden items-center justify-between border-b border-linear-border px-6 py-4 md:flex">
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-semibold tracking-tight text-linear-text">
            LogYourBody
          </h1>
          {!isOnline && (
            <Badge variant="outline" className="text-xs border-yellow-500/50 text-yellow-500">
              Offline
            </Badge>
          )}
          <SyncStatus />
        </div>
        <div className="flex gap-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                className="bg-linear-purple text-white hover:bg-linear-purple/90 font-medium"
              >
                <Plus className="h-4 w-4 mr-2" />
                Add Data
                <ChevronDown className="h-4 w-4 ml-2" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem onClick={() => router.push('/log')}>
                <Plus className="h-4 w-4 mr-2" />
                Log Metrics
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => router.push('/import')}>
                <Upload className="h-4 w-4 mr-2" />
                Bulk Import
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button
            size="icon"
            variant="ghost"
            onClick={() => router.push('/settings')}
            className="h-10 w-10 text-linear-text-secondary transition-colors hover:bg-linear-border/50 hover:text-linear-text"
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
            className="h-full flex flex-col"
            orientation="horizontal"
          >
            <TabsList
              className="grid w-full grid-cols-2 bg-linear-card border-b border-linear-border rounded-none"
              onKeyDown={(e) => {
                // Disable arrow key navigation for tabs
                if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                  e.preventDefault()
                  e.stopPropagation()
                }
              }}
            >
              <TabsTrigger value="0" className="data-[state=active]:bg-linear-border/50">Body Model</TabsTrigger>
              <TabsTrigger value="1" className="data-[state=active]:bg-linear-border/50">Photo</TabsTrigger>
            </TabsList>

            <TabsContent value="0" className="flex-1 m-0">
              <Suspense fallback={
                <div className="flex h-full items-center justify-center bg-linear-bg">
                  <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" />
                </div>
              }>
                <AvatarDisplay
                  gender={profile?.gender}
                  bodyFatPercentage={displayValues?.bodyFatPercentage}
                  showPhoto={false}
                  className="h-full w-full"
                  onAddPhoto={() => router.push('/log')}
                />
              </Suspense>
            </TabsContent>

            <TabsContent value="1" className="flex-1 m-0">
              <Suspense fallback={
                <div className="flex h-full items-center justify-center bg-linear-bg">
                  <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" />
                </div>
              }>
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
        <div className="min-h-0 flex-[0.8] border-linear-border md:w-1/3 md:flex-1 md:border-l">
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
  )
}
