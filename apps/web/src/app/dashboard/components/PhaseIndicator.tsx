import { Badge } from '@/components/ui/badge'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import { TrendingDown, TrendingUp, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { PhaseResult } from '@/utils/phase-calculator'

export function PhaseIndicator({ phaseData }: { phaseData: PhaseResult | null }) {
  if (!phaseData || phaseData.phase === 'insufficient-data') {
    return (
      <div className="bg-linear-bg rounded-lg p-4 border border-linear-border">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <TrendingUp className="h-4 w-4 text-linear-text-tertiary" />
            <span className="text-xs text-linear-text-secondary">Current Phase</span>
          </div>
        </div>
        <div className="mt-2">
          <span className="text-lg font-semibold text-linear-text-tertiary">
            Need more data
          </span>
          <p className="text-xs text-linear-text-tertiary mt-1">
            Log weight for 3 weeks to see phase
          </p>
        </div>
      </div>
    );
  }

  const getPhaseIcon = () => {
    switch (phaseData.phase) {
      case 'cutting':
        return <TrendingDown className="h-4 w-4 text-red-400" />;
      case 'bulking':
        return <TrendingUp className="h-4 w-4 text-green-400" />;
      case 'maintaining':
        return <Minus className="h-4 w-4 text-blue-400" />;
      default:
        return <TrendingUp className="h-4 w-4 text-linear-text-tertiary" />;
    }
  };

  const getPhaseColor = () => {
    switch (phaseData.phase) {
      case 'cutting':
        return 'text-red-400';
      case 'bulking':
        return 'text-green-400';
      case 'maintaining':
        return 'text-blue-400';
      default:
        return 'text-linear-text-tertiary';
    }
  };

  return (
    <div className="bg-linear-bg rounded-lg p-4 border border-linear-border">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {getPhaseIcon()}
          <span className="text-xs text-linear-text-secondary">Current Phase</span>
        </div>
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger>
              <Badge variant="outline" className="text-xs capitalize">
                {phaseData.confidence} confidence
              </Badge>
            </TooltipTrigger>
            <TooltipContent>
              <p className="text-xs">Based on {phaseData.confidence === 'high' ? '6+' : phaseData.confidence === 'medium' ? '4-5' : '3'} data points</p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </div>
      <div className="mt-2">
        <span className={cn("text-2xl font-bold capitalize", getPhaseColor())}>
          {phaseData.phase}
        </span>
        <p className="text-sm text-linear-text-secondary mt-1">
          {phaseData.message}
        </p>
      </div>
    </div>
  );
}
