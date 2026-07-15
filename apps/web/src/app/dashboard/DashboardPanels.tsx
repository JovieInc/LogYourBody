'use client';

import { useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import Image from 'next/image';
import { Camera, Info, Plus, User } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { BodyFatScale } from '@/components/BodyFatScale';
import { usesIndividualizedAestheticGoals } from '@/lib/flags/aesthetic-goals';
import { UserProfile } from '@/types/body-metrics';
import { calculateFFMI, getBodyFatCategory, convertWeight } from '@/utils/body-calculations';
import { getAvatarUrl } from '@/utils/avatar-utils';
import { cn } from '@/lib/utils';
import { getTimelineDisplayValues, TimelineEntry } from '@/utils/data-interpolation';
import { PhaseResult } from '@/utils/phase-calculator';
import { getMetricsTrends, getTrendArrow, getTrendColorClass } from '@/utils/trend-calculator';

const PhaseIndicator = dynamic(
  () => import('./components/PhaseIndicator').then((mod) => ({ default: mod.PhaseIndicator })),
  {
    loading: () => (
      <div className="bg-linear-bg border-linear-border h-24 animate-pulse rounded-lg border p-4" />
    ),
  },
);

// Components extracted to separate files for better code splitting

// Avatar display component
export const AvatarDisplay = ({
  gender,
  bodyFatPercentage,
  showPhoto,
  profileImage,
  className,
  onAddPhoto,
}: {
  gender?: string;
  bodyFatPercentage?: number;
  showPhoto?: boolean;
  profileImage?: string;
  className?: string;
  onAddPhoto?: () => void;
}) => {
  const [imageError, setImageError] = useState(false);

  if (showPhoto) {
    if (profileImage) {
      return (
        <div className={cn('bg-linear-bg relative flex items-center justify-center', className)}>
          <Image src={profileImage} alt="Profile" fill className="object-cover" />
        </div>
      );
    } else {
      // No photo available - show add photo prompt
      return (
        <div className={cn('bg-linear-bg relative flex items-center justify-center', className)}>
          <div className="text-center">
            <Camera className="text-linear-text-tertiary mx-auto mb-4 h-24 w-24" />
            <p className="text-linear-text-secondary mb-4">No photo yet</p>
            <Button variant="outline" className="border-linear-border" onClick={onAddPhoto}>
              <Plus className="mr-2 h-4 w-4" />
              Add Photo
            </Button>
          </div>
        </div>
      );
    }
  }

  const avatarUrl = getAvatarUrl(gender as 'male' | 'female', bodyFatPercentage);

  return (
    <div className={cn('bg-linear-bg relative flex items-center justify-center p-8', className)}>
      {avatarUrl && !imageError ? (
        <Image
          src={avatarUrl}
          alt={`Body silhouette at ${bodyFatPercentage || 20}% body fat`}
          width={300}
          height={400}
          className="h-full max-h-[500px] w-auto object-contain"
          onError={() => setImageError(true)}
        />
      ) : (
        <div className="text-center">
          <User className="text-linear-text-tertiary mx-auto mb-4 h-24 w-24" />
          <p className="mb-2 text-white">No body model yet</p>
          <p className="text-linear-text-secondary mb-4 text-sm">
            Add your measurements to generate one
          </p>
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
  );
};

// Profile Panel component
export const ProfilePanel = ({
  entry,
  user,
  formattedHeight,
  phaseData,
  trends,
}: {
  entry: TimelineEntry | null;
  user: UserProfile | null;
  formattedHeight: string;
  phaseData: PhaseResult | null;
  trends: ReturnType<typeof getMetricsTrends>;
}) => {
  const rawValues = useMemo(() => (entry ? getTimelineDisplayValues(entry) : null), [entry]);

  const getDisplayName = () => {
    if (!user) return 'User';

    const fullName = (user.full_name || '').trim();
    if (fullName.length > 0) {
      return fullName.split(/\s+/)[0];
    }

    if (user.email) {
      return user.email.split('@')[0];
    }

    return 'User';
  };

  // Convert weight from kg (database storage) to user's preferred unit
  const displayValues = useMemo(() => {
    if (!rawValues) return null;
    return {
      ...rawValues,
      weight:
        rawValues.weight && user?.settings?.units?.weight === 'lbs'
          ? convertWeight(rawValues.weight, 'kg', 'lbs')
          : rawValues.weight,
    };
  }, [rawValues, user?.settings?.units?.weight]);

  const bodyFatCategory = useMemo(
    () =>
      displayValues?.bodyFatPercentage && user?.gender
        ? getBodyFatCategory(displayValues.bodyFatPercentage, user.gender as 'male' | 'female')
        : null,
    [displayValues?.bodyFatPercentage, user?.gender],
  );

  // Calculate age from date of birth
  const age = useMemo(() => {
    if (!user?.date_of_birth) return null;
    try {
      const birthDate = new Date(user.date_of_birth);
      const today = new Date();
      let age = today.getFullYear() - birthDate.getFullYear();
      const monthDiff = today.getMonth() - birthDate.getMonth();
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--;
      }
      return age;
    } catch {
      return null;
    }
  }, [user?.date_of_birth]);

  return (
    <div className="bg-linear-card h-full overflow-y-auto p-6">
      <div className="space-y-6">
        {/* User Info */}
        <div className="flex items-start justify-between">
          {/* Left side - Name and email */}
          <div>
            <h2 className="text-linear-text mb-1 text-2xl font-bold">{getDisplayName()}</h2>
            <p className="text-linear-text-secondary text-sm">{user?.email}</p>
          </div>

          {/* Right side - Metrics */}
          <div className="text-right">
            <div className="text-linear-text-secondary text-sm">
              {[
                age && `${age}y`,
                user?.height && formattedHeight,
                user?.gender && (user.gender === 'male' ? 'Male' : 'Female'),
              ]
                .filter(Boolean)
                .join(' • ')}
            </div>
          </div>
        </div>

        {/* Current Stats */}
        <div className="space-y-4">
          <h3 className="text-linear-text text-sm font-semibold uppercase tracking-wider">
            Current Stats
          </h3>

          {/* Stats Grid - Mobile optimized with horizontal scroll */}
          <div className="-mx-6 flex gap-3 overflow-x-auto px-6 pb-2 md:mx-0 md:grid md:grid-cols-2 md:overflow-visible md:px-0 md:pb-0">
            {/* Weight */}
            <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4 md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="text-linear-text-secondary mb-2 text-xs uppercase tracking-wider">
                  Weight
                </div>
                <div className="flex items-baseline gap-1">
                  <span className="text-linear-text text-4xl font-bold md:text-3xl">
                    {displayValues?.weight?.toFixed(1) || '--'}
                  </span>
                  <span className="text-linear-text-secondary text-lg font-medium md:text-sm">
                    {user?.settings?.units?.weight || 'lbs'}
                  </span>
                </div>
                <div className="mt-2 flex h-6 items-center gap-1">
                  {trends.weight.direction !== 'unknown' && (
                    <span
                      className={cn(
                        'text-sm font-medium',
                        getTrendColorClass(trends.weight.direction, 'weight'),
                      )}
                    >
                      {getTrendArrow(trends.weight.direction)}
                      {trends.weight.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.weight.difference > 0 ? '+' : ''}
                          {trends.weight.difference.toFixed(1)}{' '}
                          {user?.settings?.units?.weight || 'lbs'}
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Body Fat */}
            <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4 md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="mb-2 flex items-center gap-1">
                  <span className="text-linear-text-secondary text-xs uppercase tracking-wider">
                    Body Fat
                  </span>
                  {displayValues?.isInferred && (
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger>
                          <Info className="text-linear-text-tertiary h-3 w-3" />
                        </TooltipTrigger>
                        <TooltipContent>
                          <p className="text-xs">Interpolated ({displayValues.confidenceLevel})</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  )}
                </div>
                <div className="flex items-baseline gap-0.5">
                  <span className="text-linear-text text-4xl font-bold md:text-3xl">
                    {displayValues?.bodyFatPercentage?.toFixed(1) || '--'}
                  </span>
                  <span className="text-linear-text-secondary text-2xl font-medium md:text-xl">
                    %
                  </span>
                </div>
                {bodyFatCategory && (
                  <div className="text-linear-text-tertiary mt-1 text-xs">{bodyFatCategory}</div>
                )}
                <div className="mt-2 flex h-6 items-center gap-1">
                  {trends.bodyFat.direction !== 'unknown' && (
                    <span
                      className={cn(
                        'text-sm font-medium',
                        getTrendColorClass(trends.bodyFat.direction, 'bodyFat'),
                      )}
                    >
                      {getTrendArrow(trends.bodyFat.direction)}
                      {trends.bodyFat.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.bodyFat.difference > 0 ? '+' : ''}
                          {trends.bodyFat.percentage.toFixed(1)}%
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Lean Mass */}
            <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4 md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="text-linear-text-secondary mb-2 text-xs uppercase tracking-wider">
                  Lean Mass
                </div>
                {displayValues?.weight && displayValues?.bodyFatPercentage ? (
                  <>
                    <div className="flex items-baseline gap-1">
                      <span className="text-linear-text text-4xl font-bold md:text-3xl">
                        {(
                          displayValues.weight *
                          (1 - displayValues.bodyFatPercentage / 100)
                        ).toFixed(1)}
                      </span>
                      <span className="text-linear-text-secondary text-lg font-medium md:text-sm">
                        {user?.settings?.units?.weight || 'lbs'}
                      </span>
                    </div>
                  </>
                ) : (
                  <div>
                    <span className="text-linear-text-tertiary text-4xl font-bold md:text-3xl">
                      --
                    </span>
                  </div>
                )}
                <div className="mt-2 flex h-6 items-center gap-1">
                  {trends.leanMass.direction !== 'unknown' && (
                    <span
                      className={cn(
                        'text-sm font-medium',
                        getTrendColorClass(trends.leanMass.direction, 'leanMass'),
                      )}
                    >
                      {getTrendArrow(trends.leanMass.direction)}
                      {trends.leanMass.direction !== 'stable' && (
                        <span className="ml-1">
                          {trends.leanMass.difference > 0 ? '+' : ''}
                          {trends.leanMass.difference.toFixed(1)}{' '}
                          {user?.settings?.units?.weight || 'lbs'}
                        </span>
                      )}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* FFMI */}
            <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4 md:min-w-0">
              <div className="flex flex-col items-center text-center">
                <div className="mb-2 flex items-center gap-1">
                  <span className="text-linear-text-secondary text-xs uppercase tracking-wider">
                    FFMI
                  </span>
                  {displayValues?.isInferred &&
                    displayValues?.weight &&
                    displayValues?.bodyFatPercentage &&
                    user?.height && (
                      <TooltipProvider>
                        <Tooltip>
                          <TooltipTrigger>
                            <Info className="text-linear-text-tertiary h-3 w-3" />
                          </TooltipTrigger>
                          <TooltipContent>
                            <p className="text-xs">Calculated from interpolated values</p>
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    )}
                </div>
                {displayValues?.weight && displayValues?.bodyFatPercentage && user?.height ? (
                  <>
                    <div>
                      <span className="text-linear-text text-4xl font-bold md:text-3xl">
                        {(() => {
                          // displayValues.weight is already in user's preferred unit
                          // rawValues.weight is in kg (database storage)
                          const weightInKg = rawValues?.weight || 0;

                          const heightInCm =
                            user?.settings?.units?.height === 'ft'
                              ? user.height * 2.54
                              : user.height;

                          return calculateFFMI(
                            weightInKg,
                            heightInCm,
                            displayValues.bodyFatPercentage,
                          ).normalized_ffmi.toFixed(1);
                        })()}
                      </span>
                    </div>
                    <div className="text-linear-text-tertiary mt-1 text-xs">
                      {(() => {
                        // displayValues.weight is already in user's preferred unit
                        // rawValues.weight is in kg (database storage)
                        const weightInKg = rawValues?.weight || 0;

                        const heightInCm =
                          user?.settings?.units?.height === 'ft' ? user.height * 2.54 : user.height;

                        const interpretation = calculateFFMI(
                          weightInKg,
                          heightInCm,
                          displayValues.bodyFatPercentage,
                        ).interpretation;
                        // Convert snake_case to Title Case
                        return interpretation
                          .split('_')
                          .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
                          .join(' ');
                      })()}
                    </div>
                    <div className="mt-2 flex h-6 items-center gap-1">
                      {trends.ffmi.direction !== 'unknown' && (
                        <span
                          className={cn(
                            'text-sm font-medium',
                            getTrendColorClass(trends.ffmi.direction, 'ffmi'),
                          )}
                        >
                          {getTrendArrow(trends.ffmi.direction)}
                          {trends.ffmi.direction !== 'stable' && (
                            <span className="ml-1">
                              {trends.ffmi.difference > 0 ? '+' : ''}
                              {trends.ffmi.difference.toFixed(1)}
                            </span>
                          )}
                        </span>
                      )}
                    </div>
                  </>
                ) : (
                  <>
                    <div>
                      <span className="text-linear-text-tertiary text-4xl font-bold md:text-3xl">
                        --
                      </span>
                    </div>
                    <div className="text-linear-text-tertiary mt-1 text-xs">Needs more data</div>
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
          <h3 className="text-linear-text text-sm font-semibold uppercase tracking-wider">
            Goals Progress
          </h3>

          <div className="space-y-4">
            {/* FFMI Goal */}
            <div>
              <div className="mb-2 flex items-center justify-between">
                <span className="text-linear-text text-sm">FFMI Goal</span>
                <span className="text-linear-text text-sm font-medium">
                  {displayValues?.weight && displayValues?.bodyFatPercentage && user?.height ? (
                    <>
                      {(() => {
                        // displayValues.weight is already in user's preferred unit
                        // rawValues.weight is in kg (database storage)
                        const weightInKg = rawValues?.weight || 0;

                        const heightInCm =
                          user?.settings?.units?.height === 'ft' ? user.height * 2.54 : user.height;

                        return calculateFFMI(
                          weightInKg,
                          heightInCm,
                          displayValues.bodyFatPercentage,
                        ).normalized_ffmi.toFixed(1);
                      })()}{' '}
                      / 22
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
                        const weightInKg = rawValues?.weight || 0;

                        const heightInCm =
                          user?.settings?.units?.height === 'ft' ? user.height * 2.54 : user.height;

                        const ffmi = calculateFFMI(
                          weightInKg,
                          heightInCm,
                          displayValues.bodyFatPercentage,
                        );
                        return Math.min(100, (ffmi.normalized_ffmi / 22) * 100);
                      })()
                    : 0
                }
                className="h-2"
              />
            </div>

            {/* Body Fat Goal */}
            <div>
              <div className="mb-2">
                <span className="text-linear-text text-sm">Body Fat Goal</span>
              </div>
              <BodyFatScale
                currentBF={displayValues?.bodyFatPercentage}
                gender={user?.gender as 'male' | 'female' | undefined}
                goalRange={
                  usesIndividualizedAestheticGoals()
                    ? undefined
                    : user?.gender === 'female'
                      ? { min: 18, max: 22 }
                      : { min: 8, max: 12 }
                }
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
