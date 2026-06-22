'use client';

import type { ChangeEvent, Dispatch, SetStateAction } from 'react';
import Image from 'next/image';
import { format } from 'date-fns';
import { AlertCircle, Camera, Percent, User, X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { cn } from '@/lib/utils';
import { UserProfile } from '@/types/body-metrics';

type Step = 'weight' | 'method' | 'measurements' | 'photo' | 'review';
type BodyFatMethod = 'simple' | 'navy' | '3-site';

type MobileLogFormData = {
  weight: string;
  weight_unit: 'kg' | 'lbs';
  method: BodyFatMethod;
  body_fat_percentage: number | null;
  neck: string;
  waist: string;
  hip: string;
  chest: string;
  abdominal: string;
  thigh: string;
  tricep: string;
  suprailiac: string;
  photo: File | null;
  photoPreview: string | null;
  notes: string;
};

type MobileProfile = {
  height?: number;
  height_unit?: 'cm' | 'ft';
  gender?: 'male' | 'female';
  settings?: UserProfile['settings'];
};

type BodyComposition = {
  lean_mass: number;
  fat_mass: number;
} | null;

type FfmiData = {
  normalized_ffmi: number;
} | null;

interface MobileLogStepContentProps {
  currentStep: Step;
  formData: MobileLogFormData;
  setFormData: Dispatch<SetStateAction<MobileLogFormData>>;
  profile: MobileProfile;
  bodyComp: BodyComposition;
  ffmiData: FfmiData;
  isUploadingPhoto: boolean;
  setShowWeightModal: (value: boolean) => void;
  setShowBodyFatModal: (value: boolean) => void;
  handlePhotoUpload: (event: ChangeEvent<HTMLInputElement>) => void;
  removePhoto: () => void;
}

export function MobileLogStepContent({
  currentStep,
  formData,
  setFormData,
  profile,
  bodyComp,
  ffmiData,
  isUploadingPhoto,
  setShowWeightModal,
  setShowBodyFatModal,
  handlePhotoUpload,
  removePhoto,
}: MobileLogStepContentProps) {
  return (
    <>
      {currentStep === 'weight' && (
        <div className="space-y-8">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-3xl font-bold">Current Weight</h2>
            <p className="text-linear-text-secondary">How much do you weigh today?</p>
          </div>

          {/* Weight requirement message */}
          <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 dark:border-amber-800 dark:bg-amber-950/20">
            <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0 text-amber-600 dark:text-amber-500" />
            <div className="text-sm text-amber-800 dark:text-amber-300">
              <p className="font-medium">Weight entry is required</p>
              <p className="mt-1 text-amber-700 dark:text-amber-400">
                Tap the box below to enter your weight
              </p>
            </div>
          </div>

          <button onClick={() => setShowWeightModal(true)} className="w-full">
            <div
              className={`rounded-2xl border-2 p-8 text-center transition-all ${
                formData.weight
                  ? 'bg-linear-card border-linear-border hover:border-linear-purple/50'
                  : 'bg-linear-purple/10 border-linear-purple hover:bg-linear-purple/20 animate-pulse'
              }`}
            >
              {formData.weight ? (
                <div className="space-y-1">
                  <div className="text-linear-text text-5xl font-bold">{formData.weight}</div>
                  <div className="text-linear-text-secondary text-xl">{formData.weight_unit}</div>
                </div>
              ) : (
                <div className="space-y-2">
                  <User className="text-linear-purple mx-auto h-12 w-12" />
                  <div className="text-linear-text text-xl font-medium">Tap to enter weight</div>
                </div>
              )}
            </div>
          </button>

          <div className="flex justify-center">
            <ToggleGroup
              type="single"
              value={formData.weight_unit}
              onValueChange={(value) =>
                value && setFormData((prev) => ({ ...prev, weight_unit: value as 'kg' | 'lbs' }))
              }
              className="bg-linear-card rounded-lg p-1"
            >
              <ToggleGroupItem
                value="lbs"
                className="data-[state=on]:bg-linear-purple px-8 data-[state=on]:text-white"
              >
                lbs
              </ToggleGroupItem>
              <ToggleGroupItem
                value="kg"
                className="data-[state=on]:bg-linear-purple px-8 data-[state=on]:text-white"
              >
                kg
              </ToggleGroupItem>
            </ToggleGroup>
          </div>
        </div>
      )}

      {currentStep === 'method' && (
        <div className="space-y-8">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-3xl font-bold">Body Fat Method</h2>
            <p className="text-linear-text-secondary">How do you want to track body fat?</p>
          </div>

          <RadioGroup
            value={formData.method}
            onValueChange={(value) =>
              value && setFormData((prev) => ({ ...prev, method: value as BodyFatMethod }))
            }
            className="space-y-4"
          >
            <label htmlFor="simple" className="block">
              <div
                className={cn(
                  'cursor-pointer rounded-xl border-2 p-6 transition-all',
                  formData.method === 'simple'
                    ? 'border-linear-purple bg-linear-purple/10'
                    : 'border-linear-border hover:border-linear-border/70',
                )}
              >
                <div className="flex items-start gap-4">
                  <RadioGroupItem value="simple" id="simple" className="mt-1" />
                  <div className="flex-1">
                    <div className="text-linear-text mb-1 font-semibold">Simple Entry</div>
                    <div className="text-linear-text-secondary text-sm">
                      I'll enter my body fat % directly
                    </div>
                  </div>
                </div>
              </div>
            </label>

            <label htmlFor="navy" className="block">
              <div
                className={cn(
                  'cursor-pointer rounded-xl border-2 p-6 transition-all',
                  formData.method === 'navy'
                    ? 'border-linear-purple bg-linear-purple/10'
                    : 'border-linear-border hover:border-linear-border/70',
                )}
              >
                <div className="flex items-start gap-4">
                  <RadioGroupItem value="navy" id="navy" className="mt-1" />
                  <div className="flex-1">
                    <div className="text-linear-text mb-1 font-semibold">Navy Method</div>
                    <div className="text-linear-text-secondary text-sm">
                      Calculate using waist, neck, and hip measurements
                    </div>
                  </div>
                </div>
              </div>
            </label>

            <label htmlFor="3-site" className="block">
              <div
                className={cn(
                  'cursor-pointer rounded-xl border-2 p-6 transition-all',
                  formData.method === '3-site'
                    ? 'border-linear-purple bg-linear-purple/10'
                    : 'border-linear-border hover:border-linear-border/70',
                )}
              >
                <div className="flex items-start gap-4">
                  <RadioGroupItem value="3-site" id="3-site" className="mt-1" />
                  <div className="flex-1">
                    <div className="text-linear-text mb-1 font-semibold">3-Site Skinfold</div>
                    <div className="text-linear-text-secondary text-sm">
                      Most accurate with calipers
                    </div>
                  </div>
                </div>
              </div>
            </label>
          </RadioGroup>
        </div>
      )}

      {currentStep === 'measurements' && (
        <div className="space-y-8">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-3xl font-bold">
              {formData.method === 'simple' ? 'Body Fat %' : 'Measurements'}
            </h2>
            <p className="text-linear-text-secondary">
              {formData.method === 'simple'
                ? 'Enter your body fat percentage'
                : 'Enter your measurements for calculation'}
            </p>
          </div>

          {formData.method === 'simple' && (
            <button onClick={() => setShowBodyFatModal(true)} className="w-full">
              <div className="bg-linear-card border-linear-border hover:border-linear-purple/50 rounded-2xl border-2 p-8 text-center transition-colors">
                {formData.body_fat_percentage ? (
                  <div className="space-y-1">
                    <div className="text-linear-text text-5xl font-bold">
                      {formData.body_fat_percentage}%
                    </div>
                    <div className="text-linear-text-secondary text-xl">Body Fat</div>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <Percent className="text-linear-text-tertiary mx-auto h-12 w-12" />
                    <div className="text-linear-text-secondary text-xl">
                      Tap to enter body fat %
                    </div>
                  </div>
                )}
              </div>
            </button>
          )}

          {formData.method === 'navy' && (
            <div className="space-y-6">
              <div>
                <Label htmlFor="neck" className="text-linear-text mb-2 block">
                  Neck ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                </Label>
                <Input
                  id="neck"
                  type="number"
                  step="0.1"
                  value={formData.neck}
                  onChange={(e) => setFormData((prev) => ({ ...prev, neck: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="15.0"
                />
              </div>

              <div>
                <Label htmlFor="waist" className="text-linear-text mb-2 block">
                  Waist ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                </Label>
                <Input
                  id="waist"
                  type="number"
                  step="0.1"
                  value={formData.waist}
                  onChange={(e) => setFormData((prev) => ({ ...prev, waist: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="33.5"
                />
                <p className="text-linear-text-tertiary mt-1 text-xs">Measure at navel level</p>
              </div>

              {profile.gender === 'female' && (
                <div>
                  <Label htmlFor="hip" className="text-linear-text mb-2 block">
                    Hip ({profile.settings?.units?.measurements === 'cm' ? 'cm' : 'in'})
                  </Label>
                  <Input
                    id="hip"
                    type="number"
                    step="0.1"
                    value={formData.hip}
                    onChange={(e) => setFormData((prev) => ({ ...prev, hip: e.target.value }))}
                    className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                    placeholder="37.5"
                  />
                  <p className="text-linear-text-tertiary mt-1 text-xs">Measure at widest point</p>
                </div>
              )}
            </div>
          )}

          {formData.method === '3-site' && profile.gender === 'male' && (
            <div className="space-y-6">
              <div>
                <Label htmlFor="chest" className="text-linear-text mb-2 block">
                  Chest (mm)
                </Label>
                <Input
                  id="chest"
                  type="number"
                  step="0.1"
                  value={formData.chest}
                  onChange={(e) => setFormData((prev) => ({ ...prev, chest: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="10"
                />
              </div>

              <div>
                <Label htmlFor="abdominal" className="text-linear-text mb-2 block">
                  Abdominal (mm)
                </Label>
                <Input
                  id="abdominal"
                  type="number"
                  step="0.1"
                  value={formData.abdominal}
                  onChange={(e) => setFormData((prev) => ({ ...prev, abdominal: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="20"
                />
              </div>

              <div>
                <Label htmlFor="thigh" className="text-linear-text mb-2 block">
                  Thigh (mm)
                </Label>
                <Input
                  id="thigh"
                  type="number"
                  step="0.1"
                  value={formData.thigh}
                  onChange={(e) => setFormData((prev) => ({ ...prev, thigh: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="15"
                />
              </div>
            </div>
          )}

          {formData.method === '3-site' && profile.gender === 'female' && (
            <div className="space-y-6">
              <div>
                <Label htmlFor="tricep" className="text-linear-text mb-2 block">
                  Tricep (mm)
                </Label>
                <Input
                  id="tricep"
                  type="number"
                  step="0.1"
                  value={formData.tricep}
                  onChange={(e) => setFormData((prev) => ({ ...prev, tricep: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="15"
                />
              </div>

              <div>
                <Label htmlFor="suprailiac" className="text-linear-text mb-2 block">
                  Suprailiac (mm)
                </Label>
                <Input
                  id="suprailiac"
                  type="number"
                  step="0.1"
                  value={formData.suprailiac}
                  onChange={(e) => setFormData((prev) => ({ ...prev, suprailiac: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="12"
                />
              </div>

              <div>
                <Label htmlFor="thigh" className="text-linear-text mb-2 block">
                  Thigh (mm)
                </Label>
                <Input
                  id="thigh"
                  type="number"
                  step="0.1"
                  value={formData.thigh}
                  onChange={(e) => setFormData((prev) => ({ ...prev, thigh: e.target.value }))}
                  className="bg-linear-card border-linear-border text-linear-text h-14 text-lg"
                  placeholder="20"
                />
              </div>
            </div>
          )}
        </div>
      )}

      {currentStep === 'photo' && (
        <div className="space-y-8">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-3xl font-bold">Progress Photo</h2>
            <p className="text-linear-text-secondary">Track your visual progress (optional)</p>
          </div>

          {formData.photoPreview ? (
            <div className="relative">
              <div className="bg-linear-card border-linear-border overflow-hidden rounded-2xl border">
                <Image
                  src={formData.photoPreview}
                  alt="Progress photo"
                  width={400}
                  height={600}
                  className="h-auto w-full"
                />
              </div>
              <button
                onClick={removePhoto}
                className="bg-linear-bg/80 border-linear-border absolute right-4 top-4 rounded-full border p-2 backdrop-blur-sm"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          ) : (
            <label className="block cursor-pointer">
              <input
                type="file"
                accept="image/*"
                onChange={handlePhotoUpload}
                className="hidden"
                disabled={isUploadingPhoto}
              />
              <div className="bg-linear-card border-linear-border hover:border-linear-purple/50 rounded-2xl border-2 border-dashed p-12 text-center transition-colors">
                {isUploadingPhoto ? (
                  <div className="border-linear-purple mx-auto h-12 w-12 animate-spin rounded-full border-b-2"></div>
                ) : (
                  <>
                    <Camera className="text-linear-text-tertiary mx-auto mb-4 h-16 w-16" />
                    <div className="text-linear-text-secondary mb-2 text-xl">
                      Add progress photo
                    </div>
                    <div className="text-linear-text-tertiary text-sm">
                      Tap to select from camera or gallery
                    </div>
                  </>
                )}
              </div>
            </label>
          )}
        </div>
      )}

      {currentStep === 'review' && (
        <div className="space-y-8">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-3xl font-bold">Review & Save</h2>
            <p className="text-linear-text-secondary">Confirm your entries before saving</p>
          </div>

          <div className="bg-linear-card space-y-4 rounded-2xl p-6">
            <div className="border-linear-border flex items-center justify-between border-b py-3">
              <span className="text-linear-text-secondary">Date</span>
              <span className="text-linear-text font-medium">
                {format(new Date(), 'MMMM d, yyyy')}
              </span>
            </div>

            <div className="border-linear-border flex items-center justify-between border-b py-3">
              <span className="text-linear-text-secondary">Weight</span>
              <span className="text-linear-text font-medium">
                {formData.weight} {formData.weight_unit}
              </span>
            </div>

            {formData.body_fat_percentage && (
              <>
                <div className="border-linear-border flex items-center justify-between border-b py-3">
                  <span className="text-linear-text-secondary">Body Fat %</span>
                  <span className="text-linear-text font-medium">
                    {formData.body_fat_percentage.toFixed(1)}%
                  </span>
                </div>

                {bodyComp && (
                  <>
                    <div className="border-linear-border flex items-center justify-between border-b py-3">
                      <span className="text-linear-text-secondary">Lean Mass</span>
                      <span className="text-linear-text font-medium">
                        {(formData.weight_unit === 'lbs'
                          ? bodyComp.lean_mass * 2.20462
                          : bodyComp.lean_mass
                        ).toFixed(1)}{' '}
                        {formData.weight_unit}
                      </span>
                    </div>

                    <div className="border-linear-border flex items-center justify-between border-b py-3">
                      <span className="text-linear-text-secondary">Fat Mass</span>
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
                  <div className="flex items-center justify-between py-3">
                    <span className="text-linear-text-secondary">FFMI</span>
                    <span className="text-linear-text font-medium">{ffmiData.normalized_ffmi}</span>
                  </div>
                )}
              </>
            )}
          </div>

          {/* Notes */}
          <div>
            <Label htmlFor="notes" className="text-linear-text mb-2 block">
              Notes (optional)
            </Label>
            <Input
              id="notes"
              value={formData.notes}
              onChange={(e) => setFormData((prev) => ({ ...prev, notes: e.target.value }))}
              className="bg-linear-card border-linear-border text-linear-text"
              placeholder="Any additional notes..."
            />
          </div>
        </div>
      )}
    </>
  );
}
