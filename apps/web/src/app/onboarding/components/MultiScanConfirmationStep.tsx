'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { useOnboarding } from '@/contexts/OnboardingContext'
import type { DexaScan } from '@/contexts/OnboardingContext'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { CalendarIcon, TrendingUp, Weight, Percent } from 'lucide-react'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { formatDateForDisplay } from '@/utils/date-utils'

export function MultiScanConfirmationStep() {
  const { data, updateData, nextStep, previousStep } = useOnboarding()
  const scans = (data.extractedScans || []) as DexaScan[]
  const scanCount = data.scanCount || 0

  // Initialize with all scans selected
  const [selectedScans, setSelectedScans] = useState<number[]>(() =>
    scans.map((_, index) => index)
  )

  const toggleScan = (index: number) => {
    setSelectedScans(prev =>
      prev.includes(index)
        ? prev.filter(i => i !== index)
        : [...prev, index]
    )
  }

  const selectAll = () => {
    setSelectedScans(scans.map((_, i) => i))
  }

  const deselectAll = () => {
    setSelectedScans([])
  }

  const handleSubmit = () => {
    const selectedScanData = selectedScans.map(i => scans[i])
    updateData({
      confirmedScans: selectedScanData,
      selectedScanCount: selectedScanData.length
    })
    nextStep()
  }

  const formatWeight = (weight: number | undefined, unit: string | undefined) => {
    if (typeof weight !== 'number') return '—'
    return `${weight.toFixed(1)} ${unit ?? ''}`
  }

  return (
    <Card className="bg-linear-card border-linear-border">
      <CardHeader>
        <CardTitle className="text-linear-text">Review Extracted Data</CardTitle>
        <CardDescription className="text-linear-text-secondary">
          We found {scanCount} scan{scanCount !== 1 ? 's' : ''} in your PDF. Select which ones to import.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Alert>
          <TrendingUp className="h-4 w-4" />
          <AlertDescription>
            Importing multiple scans helps track your progress over time and provides better insights.
          </AlertDescription>
        </Alert>

        <div className="flex items-center justify-between mb-4">
          <span className="text-sm text-linear-text-secondary">
            {selectedScans.length} of {scans.length} selected
          </span>
          <div className="flex gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={selectAll}
              className="text-xs"
            >
              Select All
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={deselectAll}
              className="text-xs"
            >
              Deselect All
            </Button>
          </div>
        </div>

        <ScrollArea className="h-[400px] pr-4">
          <div className="space-y-3">
            {scans.map((scan, index) => (
              <div
                key={index}
                className={`p-4 rounded-lg border transition-all cursor-pointer ${selectedScans.includes(index)
                    ? 'border-linear-purple bg-linear-purple/10'
                    : 'border-linear-border hover:border-linear-border/70'
                  }`}
                onClick={() => toggleScan(index)}
              >
                <div className="flex items-start gap-3">
                  <Checkbox
                    checked={selectedScans.includes(index)}
                    onCheckedChange={() => toggleScan(index)}
                    onClick={(e) => e.stopPropagation()}
                    className="mt-1"
                  />
                  <div className="flex-1 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2 text-linear-text font-medium">
                        <CalendarIcon className="h-4 w-4" />
                        {formatDateForDisplay(scan.date)}
                      </div>
                      {scan.source && (
                        <span className="text-xs text-linear-text-secondary">
                          {scan.source}
                        </span>
                      )}
                    </div>

                    <div className="grid grid-cols-2 gap-4 text-sm">
                      <div className="flex items-center gap-2">
                        <Weight className="h-3 w-3 text-linear-text-tertiary" />
                        <span className="text-linear-text-secondary">Weight:</span>
                        <span className="text-linear-text">
                          {formatWeight(scan.weight, scan.weight_unit)}
                        </span>
                      </div>

                      {scan.body_fat_percentage && (
                        <div className="flex items-center gap-2">
                          <Percent className="h-3 w-3 text-linear-text-tertiary" />
                          <span className="text-linear-text-secondary">Body Fat:</span>
                          <span className="text-linear-text">
                            {scan.body_fat_percentage.toFixed(1)}%
                          </span>
                        </div>
                      )}

                      {scan.muscle_mass && (
                        <div className="flex items-center gap-2">
                          <span className="text-linear-text-secondary">Muscle:</span>
                          <span className="text-linear-text">
                            {formatWeight(scan.muscle_mass, scan.weight_unit)}
                          </span>
                        </div>
                      )}

                      {scan.bone_mass && (
                        <div className="flex items-center gap-2">
                          <span className="text-linear-text-secondary">Bone:</span>
                          <span className="text-linear-text">
                            {formatWeight(scan.bone_mass, scan.weight_unit)}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </ScrollArea>

        <div className="flex gap-3 pt-4">
          <Button
            variant="ghost"
            onClick={previousStep}
          >
            Back
          </Button>

          <Button
            onClick={handleSubmit}
            disabled={selectedScans.length === 0}
            className="ml-auto bg-linear-purple hover:bg-linear-purple/90 text-white"
          >
            Import {selectedScans.length} Scan{selectedScans.length !== 1 ? 's' : ''}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}