'use client';

import type { ChangeEvent, Dispatch, SetStateAction } from 'react';
import Image from 'next/image';
import { format } from 'date-fns';
import { AlertCircle, Calculator, Camera, CheckCircle, Ruler, User, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Separator } from '@/components/ui/separator';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { UserProfile } from '@/types/body-metrics';

type Step = 'weight' | 'method' | 'measurements' | 'photo' | 'review';
type BodyFatMethod = 'simple' | 'navy' | '3-site' | '7-site';

type LogFormData = {
  weight: string;
  weight_unit: 'kg' | 'lbs';
  method: BodyFatMethod;
  waist: string;
  neck: string;
  hip: string;
  chest: string;
  abdominal: string;
  thigh: string;
  tricep: string;
  suprailiac: string;
  body_fat_percentage: number | null;
  notes: string;
  photo: File | null;
  photoPreview: string | null;
};

type BodyComposition = {
  lean_mass: number;
  fat_mass: number;
} | null;

type FfmiData = {
  normalized_ffmi: number;
} | null;

interface DesktopLogStepContentProps {
  currentStep: Step;
  setCurrentStep: Dispatch<SetStateAction<Step>>;
  formData: LogFormData;
  setFormData: Dispatch<SetStateAction<LogFormData>>;
  profile: Partial<UserProfile>;
  bodyComp: BodyComposition;
  ffmiData: FfmiData;
  isUploadingPhoto: boolean;
  setShowWeightModal: (value: boolean) => void;
  handlePhotoUpload: (event: ChangeEvent<HTMLInputElement>) => void;
  removePhoto: () => void;
}

export function DesktopLogStepContent({
  currentStep,
  setCurrentStep,
  formData,
  setFormData,
  profile,
  bodyComp,
  ffmiData,
  isUploadingPhoto,
  setShowWeightModal,
  handlePhotoUpload,
  removePhoto,
}: DesktopLogStepContentProps) {
  return (
    <>
      {/* Weight Step */}
      {currentStep === 'weight' && (
        <>
          <CardHeader>
            <div className="mb-2 flex items-center gap-3">
              <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                <User className="text-linear-text h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-linear-text">Current Weight</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  What's your weight today?
                </CardDescription>
              </div>
            </div>
            {/* Weight requirement message */}
            <div className="mt-4 flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 dark:border-amber-800 dark:bg-amber-950/20">
              <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0 text-amber-600 dark:text-amber-500" />
              <div className="text-sm text-amber-800 dark:text-amber-300">
                <p className="font-medium">Weight entry is required</p>
                <p className="mt-1 text-amber-700 dark:text-amber-400">
                  Please enter your current weight to continue with body composition tracking.
                </p>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Weight Display */}
            <div className="py-8 text-center">
              {formData.weight ? (
                <div>
                  <div className="text-linear-text mb-2 text-5xl font-bold">{formData.weight}</div>
                  <div className="text-linear-text-secondary text-lg">{formData.weight_unit}</div>
                </div>
              ) : (
                <div className="text-linear-text-secondary text-2xl">Tap to set weight</div>
              )}
            </div>

            {/* Action Buttons */}
            <div className="space-y-3">
              <Button
                variant={formData.weight ? 'outline' : 'default'}
                size="lg"
                className={`h-16 w-full text-lg transition-all ${
                  !formData.weight
                    ? 'bg-linear-purple hover:bg-linear-purple/90 animate-pulse text-white shadow-lg'
                    : ''
                }`}
                onClick={() => setShowWeightModal(true)}
              >
                <User className="mr-3 h-5 w-5" />
                {formData.weight ? 'Change Weight' : 'Set Your Weight'}
              </Button>

              {/* Unit Toggle */}
              <div className="flex justify-center">
                <ToggleGroup
                  type="single"
                  value={formData.weight_unit}
                  onValueChange={(value) => {
                    if (value)
                      setFormData((prev) => ({ ...prev, weight_unit: value as 'kg' | 'lbs' }));
                  }}
                >
                  <ToggleGroupItem
                    value="kg"
                    className="data-[state=on]:bg-linear-purple data-[state=on]:text-white"
                  >
                    kg
                  </ToggleGroupItem>
                  <ToggleGroupItem
                    value="lbs"
                    className="data-[state=on]:bg-linear-purple data-[state=on]:text-white"
                  >
                    lbs
                  </ToggleGroupItem>
                </ToggleGroup>
              </div>
            </div>

            <Separator className="bg-linear-border" />

            <div className="pt-2">
              <Button
                onClick={() => setCurrentStep('review')}
                variant="ghost"
                className="text-linear-text-secondary w-full"
              >
                Skip body composition →
              </Button>
            </div>
          </CardContent>
        </>
      )}

      {/* Method Step */}
      {currentStep === 'method' && (
        <>
          <CardHeader>
            <div className="mb-2 flex items-center gap-3">
              <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                <Calculator className="text-linear-text h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-linear-text">Measurement Method</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  How would you like to measure body fat?
                </CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <RadioGroup
              value={formData.method}
              onValueChange={(value) =>
                setFormData((prev) => ({
                  ...prev,
                  method: value as 'simple' | 'navy' | '3-site' | '7-site',
                }))
              }
              className="space-y-3"
            >
              <label
                htmlFor="method-simple"
                className="border-linear-border hover:bg-linear-card/50 flex cursor-pointer items-center space-x-3 rounded-lg border p-4"
              >
                <RadioGroupItem value="simple" id="method-simple" />
                <div className="flex-1">
                  <p className="text-linear-text font-medium">Simple Entry</p>
                  <p className="text-linear-text-secondary text-sm">
                    Enter your body fat % directly
                  </p>
                </div>
              </label>

              <label
                htmlFor="method-navy"
                className="border-linear-border hover:bg-linear-card/50 flex cursor-pointer items-center space-x-3 rounded-lg border p-4"
              >
                <RadioGroupItem value="navy" id="method-navy" />
                <div className="flex-1">
                  <p className="text-linear-text font-medium">Navy Method</p>
                  <p className="text-linear-text-secondary text-sm">
                    Tape measurements (±3% accuracy)
                  </p>
                </div>
              </label>

              <label
                htmlFor="method-3site"
                className="border-linear-border hover:bg-linear-card/50 flex cursor-pointer items-center space-x-3 rounded-lg border p-4"
              >
                <RadioGroupItem value="3-site" id="method-3site" />
                <div className="flex-1">
                  <p className="text-linear-text font-medium">3-Site Skinfold</p>
                  <p className="text-linear-text-secondary text-sm">
                    Caliper measurements (±2% accuracy)
                  </p>
                </div>
              </label>
            </RadioGroup>
          </CardContent>
        </>
      )}

      {/* Measurements Step */}
      {currentStep === 'measurements' && (
        <>
          <CardHeader>
            <div className="mb-2 flex items-center gap-3">
              <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                <Ruler className="text-linear-text h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-linear-text">Take Measurements</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  {formData.method === 'simple' && 'Enter your body fat percentage'}
                  {formData.method === 'navy' && 'Measure with a tape measure'}
                  {formData.method === '3-site' && 'Measure with body fat calipers'}
                </CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {formData.method === 'simple' && (
              <div className="space-y-2">
                <Label htmlFor="bodyFat" className="text-linear-text">
                  Body Fat %
                </Label>
                <Input
                  id="bodyFat"
                  type="number"
                  step="0.1"
                  value={formData.body_fat_percentage || ''}
                  onChange={(e) =>
                    setFormData((prev) => ({
                      ...prev,
                      body_fat_percentage: e.target.value ? parseFloat(e.target.value) : null,
                    }))
                  }
                  className="bg-linear-bg border-linear-border text-linear-text"
                  placeholder="15.0"
                />
              </div>
            )}

            {formData.method === 'navy' && (
              <>
                <div className="space-y-2">
                  <Label htmlFor="neck" className="text-linear-text">
                    Neck ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                  </Label>
                  <Input
                    id="neck"
                    type="number"
                    step="0.1"
                    value={formData.neck}
                    onChange={(e) => setFormData((prev) => ({ ...prev, neck: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="15.0"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="waist" className="text-linear-text">
                    Waist ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                  </Label>
                  <Input
                    id="waist"
                    type="number"
                    step="0.1"
                    value={formData.waist}
                    onChange={(e) => setFormData((prev) => ({ ...prev, waist: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="33.5"
                  />
                  <p className="text-linear-text-tertiary text-xs">Measure at navel level</p>
                </div>

                {profile.gender === 'female' && (
                  <div className="space-y-2">
                    <Label htmlFor="hip" className="text-linear-text">
                      Hip ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                    </Label>
                    <Input
                      id="hip"
                      type="number"
                      step="0.1"
                      value={formData.hip}
                      onChange={(e) => setFormData((prev) => ({ ...prev, hip: e.target.value }))}
                      className="bg-linear-bg border-linear-border text-linear-text"
                      placeholder="37.5"
                    />
                    <p className="text-linear-text-tertiary text-xs">Measure at widest point</p>
                  </div>
                )}
              </>
            )}

            {formData.method === '3-site' && profile.gender === 'male' && (
              <>
                <div className="space-y-2">
                  <Label htmlFor="chest" className="text-linear-text">
                    Chest (mm)
                  </Label>
                  <Input
                    id="chest"
                    type="number"
                    step="0.1"
                    value={formData.chest}
                    onChange={(e) => setFormData((prev) => ({ ...prev, chest: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="10"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="abdominal" className="text-linear-text">
                    Abdominal (mm)
                  </Label>
                  <Input
                    id="abdominal"
                    type="number"
                    step="0.1"
                    value={formData.abdominal}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, abdominal: e.target.value }))
                    }
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="20"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="thigh" className="text-linear-text">
                    Thigh (mm)
                  </Label>
                  <Input
                    id="thigh"
                    type="number"
                    step="0.1"
                    value={formData.thigh}
                    onChange={(e) => setFormData((prev) => ({ ...prev, thigh: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="15"
                  />
                </div>
              </>
            )}

            {formData.method === '3-site' && profile.gender === 'female' && (
              <>
                <div className="space-y-2">
                  <Label htmlFor="tricep" className="text-linear-text">
                    Tricep (mm)
                  </Label>
                  <Input
                    id="tricep"
                    type="number"
                    step="0.1"
                    value={formData.tricep}
                    onChange={(e) => setFormData((prev) => ({ ...prev, tricep: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="15"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="suprailiac" className="text-linear-text">
                    Suprailiac (mm)
                  </Label>
                  <Input
                    id="suprailiac"
                    type="number"
                    step="0.1"
                    value={formData.suprailiac}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, suprailiac: e.target.value }))
                    }
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="20"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="thigh" className="text-linear-text">
                    Thigh (mm)
                  </Label>
                  <Input
                    id="thigh"
                    type="number"
                    step="0.1"
                    value={formData.thigh}
                    onChange={(e) => setFormData((prev) => ({ ...prev, thigh: e.target.value }))}
                    className="bg-linear-bg border-linear-border text-linear-text"
                    placeholder="25"
                  />
                </div>
              </>
            )}
          </CardContent>
        </>
      )}

      {/* Photo Step */}
      {currentStep === 'photo' && (
        <>
          <CardHeader>
            <div className="mb-2 flex items-center gap-3">
              <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                <Camera className="text-linear-text h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-linear-text">Progress Photo</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  Document your progress visually (optional)
                </CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {!formData.photoPreview ? (
              <div className="border-linear-border rounded-lg border-2 border-dashed py-12 text-center">
                <input
                  type="file"
                  id="photo-upload"
                  accept="image/*"
                  onChange={handlePhotoUpload}
                  className="hidden"
                  disabled={isUploadingPhoto}
                />
                <Camera className="text-linear-text-tertiary mx-auto mb-4 h-12 w-12" />
                <p className="text-linear-text-secondary mb-4">
                  {isUploadingPhoto ? 'Processing photo...' : 'No photo added'}
                </p>
                <label htmlFor="photo-upload">
                  <Button
                    variant="outline"
                    className="border-linear-border"
                    disabled={isUploadingPhoto}
                    asChild
                  >
                    <span>
                      <Camera className="mr-2 h-4 w-4" />
                      {isUploadingPhoto ? 'Processing...' : 'Choose Photo'}
                    </span>
                  </Button>
                </label>
              </div>
            ) : (
              <div className="space-y-4">
                <div className="bg-linear-border relative aspect-[3/4] overflow-hidden rounded-lg">
                  <Image
                    src={formData.photoPreview}
                    alt="Progress photo"
                    fill
                    className="object-cover"
                  />
                  <Button
                    size="icon"
                    variant="destructive"
                    className="absolute right-2 top-2"
                    onClick={removePhoto}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                </div>
                <p className="text-linear-text-secondary text-center text-sm">
                  Photo ready to upload
                </p>
              </div>
            )}
          </CardContent>
        </>
      )}

      {/* Review Step */}
      {currentStep === 'review' && (
        <>
          <CardHeader>
            <div className="mb-2 flex items-center gap-3">
              <div className="bg-linear-purple/10 flex h-10 w-10 items-center justify-center rounded-lg">
                <CheckCircle className="text-linear-text h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-linear-text">Review & Save</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  Confirm your measurements
                </CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Summary */}
            <div className="space-y-4">
              <div className="flex items-center justify-between py-2">
                <span className="text-linear-text-secondary text-sm">Date</span>
                <span className="text-linear-text font-medium">
                  {format(new Date(), 'EEEE, MMMM d, yyyy')}
                </span>
              </div>

              <Separator className="bg-linear-border" />

              <div className="flex items-center justify-between py-2">
                <span className="text-linear-text-secondary text-sm">Weight</span>
                <span className="text-linear-text font-medium">
                  {formData.weight} {formData.weight_unit}
                </span>
              </div>

              {formData.body_fat_percentage && (
                <>
                  <div className="flex items-center justify-between py-2">
                    <span className="text-linear-text-secondary text-sm">Body Fat %</span>
                    <span className="text-linear-text font-medium">
                      {formData.body_fat_percentage.toFixed(1)}%
                    </span>
                  </div>

                  {bodyComp && (
                    <>
                      <div className="flex items-center justify-between py-2">
                        <span className="text-linear-text-secondary text-sm">Lean Mass</span>
                        <span className="text-linear-text font-medium">
                          {(formData.weight_unit === 'lbs'
                            ? bodyComp.lean_mass * 2.20462
                            : bodyComp.lean_mass
                          ).toFixed(1)}{' '}
                          {formData.weight_unit}
                        </span>
                      </div>

                      <div className="flex items-center justify-between py-2">
                        <span className="text-linear-text-secondary text-sm">Fat Mass</span>
                        <span className="text-linear-text font-medium">
                          {(formData.weight_unit === 'lbs'
                            ? bodyComp.fat_mass * 2.20462
                            : bodyComp.fat_mass
                          ).toFixed(1)}{' '}
                          {formData.weight_unit}
                        </span>
                      </div>
                    </>
                  )}

                  {ffmiData && (
                    <div className="flex items-center justify-between py-2">
                      <span className="text-linear-text-secondary text-sm">FFMI</span>
                      <span className="text-linear-text font-medium">
                        {ffmiData.normalized_ffmi}
                      </span>
                    </div>
                  )}
                </>
              )}
            </div>

            {/* Photo Preview */}
            {formData.photoPreview && (
              <div className="space-y-2">
                <Label className="text-linear-text">Progress Photo</Label>
                <div className="bg-linear-border relative mx-auto aspect-[3/4] max-w-xs overflow-hidden rounded-lg">
                  <Image
                    src={formData.photoPreview}
                    alt="Progress photo"
                    fill
                    className="object-cover"
                  />
                </div>
              </div>
            )}

            {/* Notes */}
            <div className="space-y-2">
              <Label htmlFor="notes" className="text-linear-text">
                Notes (optional)
              </Label>
              <textarea
                id="notes"
                value={formData.notes}
                onChange={(e) => setFormData((prev) => ({ ...prev, notes: e.target.value }))}
                className="bg-linear-bg border-linear-border text-linear-text w-full resize-none rounded-md border px-3 py-2"
                placeholder="Any notes about today's measurement..."
                rows={3}
              />
            </div>
          </CardContent>
        </>
      )}
    </>
  );
}
