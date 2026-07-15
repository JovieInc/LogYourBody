'use client';

import { cn } from '@/lib/utils';

interface BodyFatScaleProps {
  currentBF?: number;
  gender?: 'male' | 'female';
  goalRange?: { min: number; max: number };
  className?: string;
}

const BF_RANGES = {
  male: {
    essential: {
      min: 2,
      max: 5,
      color: 'bg-gradient-to-r from-red-500/20 to-red-500/10',
      label: 'Essential',
    },
    athletes: {
      min: 6,
      max: 13,
      color: 'bg-gradient-to-r from-blue-500/20 to-blue-500/10',
      label: 'Athletes',
    },
    fitness: {
      min: 14,
      max: 17,
      color: 'bg-gradient-to-r from-green-500/20 to-green-500/10',
      label: 'Fitness',
    },
    average: {
      min: 18,
      max: 24,
      color: 'bg-gradient-to-r from-yellow-500/20 to-yellow-500/10',
      label: 'Average',
    },
    obese: {
      min: 25,
      max: 100,
      color: 'bg-gradient-to-r from-orange-500/20 to-orange-500/10',
      label: 'Obese',
    },
  },
  female: {
    essential: {
      min: 10,
      max: 13,
      color: 'bg-gradient-to-r from-red-500/20 to-red-500/10',
      label: 'Essential',
    },
    athletes: {
      min: 14,
      max: 20,
      color: 'bg-gradient-to-r from-blue-500/20 to-blue-500/10',
      label: 'Athletes',
    },
    fitness: {
      min: 21,
      max: 24,
      color: 'bg-gradient-to-r from-green-500/20 to-green-500/10',
      label: 'Fitness',
    },
    average: {
      min: 25,
      max: 31,
      color: 'bg-gradient-to-r from-yellow-500/20 to-yellow-500/10',
      label: 'Average',
    },
    obese: {
      min: 32,
      max: 100,
      color: 'bg-gradient-to-r from-orange-500/20 to-orange-500/10',
      label: 'Obese',
    },
  },
};

export function BodyFatScale({
  currentBF,
  gender = 'male',
  goalRange,
  className,
}: BodyFatScaleProps) {
  // Ensure we have a valid gender, default to male if undefined
  const validGender = gender || 'male';
  const ranges = BF_RANGES[validGender];
  const maxDisplay = 35; // Max value to display on scale

  // Calculate position percentages
  const currentPosition = currentBF ? (Math.min(currentBF, maxDisplay) / maxDisplay) * 100 : null;
  const goalStartPosition = goalRange ? (goalRange.min / maxDisplay) * 100 : null;
  const goalEndPosition = goalRange ? (goalRange.max / maxDisplay) * 100 : null;

  return (
    <div className={cn('space-y-2', className)}>
      {/* Scale bar */}
      <div className="bg-linear-bg border-linear-border relative h-6 overflow-hidden rounded border">
        {/* Background segments */}
        <div className="absolute inset-0 flex">
          {Object.entries(ranges).map(([key, range]) => {
            const startPercent = (range.min / maxDisplay) * 100;
            const endPercent = (Math.min(range.max, maxDisplay) / maxDisplay) * 100;
            const width = endPercent - startPercent;

            return (
              <div
                key={key}
                className={cn(range.color)}
                style={{
                  left: `${startPercent}%`,
                  width: `${width}%`,
                  position: 'absolute',
                  height: '100%',
                }}
              />
            );
          })}
        </div>

        {/* Goal range overlay - subtle highlight */}
        {goalStartPosition !== null && goalEndPosition !== null && (
          <div
            data-testid="body-fat-goal-range"
            className="bg-linear-purple/10 border-linear-purple/30 absolute h-full border-x"
            style={{
              left: `${goalStartPosition}%`,
              width: `${goalEndPosition - goalStartPosition}%`,
            }}
          />
        )}

        {/* Current BF% marker */}
        {currentPosition !== null && currentBF !== undefined && (
          <div
            className="bg-linear-text absolute bottom-0 top-0 w-0.5"
            style={{ left: `${currentPosition}%` }}
          >
            <div className="bg-linear-card border-linear-border text-linear-text absolute -top-6 left-1/2 -translate-x-1/2 whitespace-nowrap rounded border px-1.5 py-0.5 text-xs font-medium">
              {currentBF.toFixed(1)}%
            </div>
          </div>
        )}
      </div>

      {/* Scale labels - minimalist approach */}
      <div className="text-linear-text-tertiary flex justify-between text-xs">
        <span>0</span>
        <span>10</span>
        <span>20</span>
        <span>30%</span>
      </div>

      {/* Info row */}
      <div className="flex items-center justify-between text-xs">
        {/* Current status */}
        <div className="flex items-center gap-2">
          {currentBF !== undefined && (
            <>
              <span className="text-linear-text-secondary">Current:</span>
              <span className="text-linear-text font-medium">
                {(() => {
                  const category =
                    Object.entries(ranges).find(
                      ([_, range]) => currentBF >= range.min && currentBF <= range.max,
                    )?.[1]?.label || 'Unknown';
                  return category;
                })()}
              </span>
            </>
          )}
        </div>

        {/* Goal indicator */}
        {goalRange && (
          <div className="flex items-center gap-1.5">
            <div className="bg-linear-purple/20 border-linear-purple/30 h-2 w-2 rounded-sm border" />
            <span className="text-linear-text-secondary">
              Goal: {goalRange.min}-{goalRange.max}%
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
