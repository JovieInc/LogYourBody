import { format } from 'date-fns'
import { cn } from '@/lib/utils'
import type { TimelineEntry } from '@/utils/data-interpolation'

export function TimelineSlider({
  timeline,
  selectedIndex,
  onIndexChange
}: {
  timeline: TimelineEntry[]
  selectedIndex: number
  onIndexChange: (index: number) => void
}) {
  if (timeline.length === 0) return null

  return (
    <div className="bg-linear-card border-t border-linear-border p-4">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-linear-text-secondary">Timeline</span>
        <span className="text-xs text-linear-text-secondary">
          {selectedIndex + 1} of {timeline.length}
        </span>
      </div>
      <div className="relative">
        <input
          type="range"
          min={0}
          max={timeline.length - 1}
          value={selectedIndex}
          onChange={(e) => onIndexChange(parseInt(e.target.value))}
          className="w-full h-2 bg-linear-border rounded-lg appearance-none cursor-pointer slider relative z-10 focus:outline-none"
        />
        {/* Photo indicators */}
        <div className="absolute inset-0 flex items-center pointer-events-none">
          {timeline.map((entry, index) => {
            const position = timeline.length > 1 ? (index / (timeline.length - 1)) * 100 : 50
            const hasPhoto = !!entry.photo
            const hasMetrics = !!entry.metrics
            const hasInferred = !!entry.inferredData

            if (!hasPhoto && !hasMetrics) return null

            return (
              <div
                key={index}
                className={cn(
                  "absolute w-2 h-2 rounded-full",
                  hasPhoto && hasMetrics && "bg-green-500",
                  hasPhoto && !hasMetrics && hasInferred && "bg-blue-500",
                  hasPhoto && !hasMetrics && !hasInferred && "bg-purple-500",
                  !hasPhoto && hasMetrics && "bg-gray-400"
                )}
                style={{ left: `${position}%`, transform: 'translateX(-50%)' }}
                title={
                  hasPhoto && hasMetrics ? "Photo & data" :
                  hasPhoto && hasInferred ? "Photo with interpolated data" :
                  hasPhoto ? "Photo only" :
                  "Data only"
                }
              />
            )
          })}
        </div>
      </div>
      <div className="flex items-center justify-between mt-2">
        <span className="text-xs text-linear-text-secondary">
          {format(new Date(timeline[0].date), 'MMM d')}
        </span>
        <span className="text-xs font-medium text-linear-text">
          {format(new Date(timeline[selectedIndex].date), 'PPP')}
        </span>
        <span className="text-xs text-linear-text-secondary">
          {format(new Date(timeline[timeline.length - 1].date), 'MMM d')}
        </span>
      </div>

      {/* Legend */}
      <div className="flex items-center gap-4 mt-3 text-xs text-linear-text-secondary">
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-green-500 rounded-full" />
          <span>Photo & Data</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-blue-500 rounded-full" />
          <span>Photo (interpolated)</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-purple-500 rounded-full" />
          <span>Photo only</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-gray-400 rounded-full" />
          <span>Data only</span>
        </div>
      </div>
    </div>
  )
}
