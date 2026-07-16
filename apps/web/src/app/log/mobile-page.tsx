'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Button } from '@/components/ui/button';
// import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input';
// import { Progress } from '@/components/ui/progress'
// import { Separator } from '@/components/ui/separator'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { WeightWheelPicker, BodyFatWheelPicker } from '@/components/ui/weight-wheel-picker';
import { toast } from '@/hooks/use-toast';
import { format } from 'date-fns';
import { ArrowLeft, ArrowRight, X, Check } from 'lucide-react';
// import Link from 'next/link'
import {
  calculateNavyBodyFat,
  calculate3SiteBodyFat,
  calculateFFMI,
  calculateBodyComposition,
  convertMeasurement,
} from '@/utils/body-calculations';
import { UserProfile } from '@/types/body-metrics';
import {
  compressImage,
  validateImageFile,
  getUploadErrorMessage,
  checkBrowserSupport,
} from '@/utils/photo-upload-utils';
import { uploadToStorage } from '@/utils/storage-utils';
import { getProfile } from '@/lib/profile';
import { cn } from '@/lib/utils';
import { motion, AnimatePresence } from 'framer-motion';
import { MobileLogStepContent } from './MobileLogStepContent';

type Step = 'weight' | 'method' | 'measurements' | 'photo' | 'review';
type BodyFatMethod = 'simple' | 'navy' | '3-site';

const STEPS: Step[] = ['weight', 'method', 'measurements', 'photo', 'review'];

// const STEP_TITLES = {
//   weight: 'Weight',
//   method: 'Method',
//   measurements: 'Body Fat',
//   photo: 'Photo',
//   review: 'Review',
// } as const

export default function MobileLogPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [currentStep, setCurrentStep] = useState<Step>('weight');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showExitDialog, setShowExitDialog] = useState(false);

  // Form state
  const [formData, setFormData] = useState({
    weight: '',
    weight_unit: 'lbs' as 'kg' | 'lbs',
    method: 'simple' as BodyFatMethod,
    body_fat_percentage: null as number | null,
    // Navy method
    neck: '',
    waist: '',
    hip: '',
    // 3-site method
    chest: '',
    abdominal: '',
    thigh: '',
    tricep: '',
    suprailiac: '',
    // Photo
    photo: null as File | null,
    photoPreview: null as string | null,
    // Optional
    notes: '',
  });

  const [profile, setProfile] = useState<{
    height?: number;
    height_unit?: 'cm' | 'ft';
    gender?: 'male' | 'female';
    date_of_birth?: string;
    settings?: UserProfile['settings'];
  }>({});

  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false);
  const [showWeightModal, setShowWeightModal] = useState(false);
  const [showBodyFatModal, setShowBodyFatModal] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  useEffect(() => {
    if (user) {
      getProfile(user.id)
        .then((profileData) => {
          if (profileData) {
            setProfile({
              height: profileData.height,
              height_unit: profileData.height_unit,
              gender: profileData.gender as 'male' | 'female' | undefined,
              date_of_birth: profileData.date_of_birth,
              settings: profileData.settings,
            });

            // Update form data with user's preferred units
            if (profileData.settings?.units?.weight) {
              setFormData((prev) => ({
                ...prev,
                weight_unit: profileData.settings.units!.weight as 'kg' | 'lbs',
              }));
            }
          }
        })
        .catch((error) => {
          console.error('Error loading profile:', error);
        });
    }
  }, [user]);

  const currentStepIndex = STEPS.indexOf(currentStep);

  const handleNext = () => {
    if (currentStepIndex < STEPS.length - 1) {
      // Calculate body fat if moving from measurements step
      if (currentStep === 'measurements') {
        calculateBodyFat();
      }
      setCurrentStep(STEPS[currentStepIndex + 1]);
    }
  };

  const handleBack = () => {
    if (currentStepIndex > 0) {
      setCurrentStep(STEPS[currentStepIndex - 1]);
    }
  };

  const handleExit = () => {
    if (formData.weight || formData.body_fat_percentage) {
      setShowExitDialog(true);
    } else {
      router.push('/dashboard');
    }
  };

  const calculateAge = () => {
    if (!profile.date_of_birth) return 30; // default
    const today = new Date();
    const birthDate = new Date(profile.date_of_birth);
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--;
    }
    return age;
  };

  const calculateBodyFat = () => {
    try {
      let bodyFat: number | null = null;

      if (formData.method === 'navy' && formData.waist && formData.neck) {
        // Convert measurements to cm if they're in inches
        const measurementUnit = profile.settings?.units?.measurements || 'in';
        const waistCm =
          measurementUnit === 'in'
            ? convertMeasurement(parseFloat(formData.waist), 'in', 'cm')
            : parseFloat(formData.waist);
        const neckCm =
          measurementUnit === 'in'
            ? convertMeasurement(parseFloat(formData.neck), 'in', 'cm')
            : parseFloat(formData.neck);
        const hipCm = formData.hip
          ? measurementUnit === 'in'
            ? convertMeasurement(parseFloat(formData.hip), 'in', 'cm')
            : parseFloat(formData.hip)
          : undefined;

        // Convert height to cm if needed
        const heightCm =
          profile.settings?.units?.height === 'ft'
            ? profile.height! * 2.54 // height is stored in inches when unit is 'ft'
            : profile.height!;

        bodyFat = calculateNavyBodyFat(
          profile.gender as 'male' | 'female',
          waistCm,
          neckCm,
          heightCm,
          hipCm,
        );
      } else if (formData.method === '3-site') {
        const age = calculateAge();
        if (profile.gender === 'male' && formData.chest && formData.abdominal && formData.thigh) {
          bodyFat = calculate3SiteBodyFat(
            'male',
            age,
            parseFloat(formData.chest),
            parseFloat(formData.abdominal),
            parseFloat(formData.thigh),
          );
        } else if (
          profile.gender === 'female' &&
          formData.tricep &&
          formData.suprailiac &&
          formData.thigh
        ) {
          bodyFat = calculate3SiteBodyFat(
            'female',
            age,
            undefined,
            undefined,
            parseFloat(formData.thigh),
            parseFloat(formData.tricep),
            parseFloat(formData.suprailiac),
          );
        }
      }

      if (bodyFat !== null) {
        setFormData((prev) => ({ ...prev, body_fat_percentage: Math.round(bodyFat * 10) / 10 }));
      }
    } catch (error) {
      console.error('Error calculating body fat:', error);
    }
  };

  const handleSubmit = async () => {
    if (!user) return;

    setIsSubmitting(true);
    try {
      let photoUrl = null;

      // Upload photo if present
      if (formData.photo) {
        const fileName = `${user.id}/${Date.now()}-progress.jpg`;
        const { publicUrl, error: uploadError } = await uploadToStorage(
          'photos',
          fileName,
          formData.photo,
          { contentType: formData.photo.type },
        );

        if (uploadError) {
          throw new Error('Failed to upload photo');
        }

        photoUrl = publicUrl;
      }

      // Convert weight to kg for storage
      const weightInKg =
        formData.weight_unit === 'lbs'
          ? parseFloat(formData.weight) / 2.20462
          : parseFloat(formData.weight);

      const response = await fetch('/api/body-metrics', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          date: format(new Date(), 'yyyy-MM-dd'),
          weight: weightInKg,
          weightUnit: 'kg',
          bodyFatPercentage: formData.body_fat_percentage,
          bodyFatMethod: formData.method === 'simple' ? 'manual' : formData.method,
          notes: formData.notes || null,
          photoUrl,
          dataSource: 'manual',
        }),
      });
      if (!response.ok) throw new Error('Failed to save metrics');

      toast({
        title: 'Success!',
        description: 'Your metrics have been logged successfully.',
      });

      // Clean up photo preview
      if (formData.photoPreview) {
        URL.revokeObjectURL(formData.photoPreview);
      }

      router.push('/dashboard');
    } catch (error) {
      console.error('Submit error:', error);
      toast({
        title: 'Error',
        description:
          error instanceof Error ? error.message : 'Failed to save metrics. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const getFFMIData = () => {
    if (!formData.weight || !formData.body_fat_percentage || !profile.height) return null;
    const weight =
      formData.weight_unit === 'lbs'
        ? parseFloat(formData.weight) / 2.20462
        : parseFloat(formData.weight);

    // Convert height to cm if needed
    const heightCm =
      profile.settings?.units?.height === 'ft'
        ? profile.height * 2.54 // height is stored in inches when unit is 'ft'
        : profile.height;

    return calculateFFMI(weight, heightCm, formData.body_fat_percentage);
  };

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploadingPhoto(true);
    try {
      // Check browser support
      const support = checkBrowserSupport();
      if (!support.supported) {
        toast({
          title: 'Browser not supported',
          description: `Missing features: ${support.missingFeatures.join(', ')}`,
          variant: 'destructive',
        });
        return;
      }

      // Validate file
      const validation = validateImageFile(file);
      if (!validation.valid) {
        toast({
          title: 'Invalid file',
          description: validation.error,
          variant: 'destructive',
        });
        return;
      }

      // Compress image
      const compressedFile = await compressImage(file, {
        maxWidth: 1920,
        maxHeight: 1920,
        quality: 0.8,
      });

      // Create preview
      const preview = URL.createObjectURL(compressedFile);

      setFormData((prev) => ({
        ...prev,
        photo: compressedFile as File,
        photoPreview: preview,
      }));

      toast({
        title: 'Photo added',
        description: 'Your progress photo has been added successfully.',
      });
    } catch (error) {
      const message = getUploadErrorMessage(error);
      toast({
        title: 'Photo processing failed',
        description: message,
        variant: 'destructive',
      });
    } finally {
      setIsUploadingPhoto(false);
    }
  };

  const removePhoto = () => {
    if (formData.photoPreview) {
      URL.revokeObjectURL(formData.photoPreview);
    }
    setFormData((prev) => ({
      ...prev,
      photo: null,
      photoPreview: null,
    }));
  };

  const getBodyComposition = () => {
    if (!formData.weight || !formData.body_fat_percentage) return null;
    const weight =
      formData.weight_unit === 'lbs'
        ? parseFloat(formData.weight) / 2.20462
        : parseFloat(formData.weight);
    return calculateBodyComposition(weight, formData.body_fat_percentage);
  };

  const ffmiData = getFFMIData();
  const bodyComp = getBodyComposition();

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <div className="border-linear-purple h-8 w-8 animate-spin rounded-full border-b-2"></div>
      </div>
    );
  }

  return (
    <>
      {/* Full Screen Mobile Experience */}
      <div className="bg-linear-bg fixed inset-0 z-50 flex flex-col">
        {/* Minimal Header */}
        <div className="border-linear-border/50 flex items-center justify-between border-b px-4 py-3">
          <div className="flex items-center gap-3">
            <div className="flex gap-1.5">
              {STEPS.map((step, index) => (
                <div
                  key={step}
                  className={cn(
                    'h-1.5 rounded-full transition-all duration-300',
                    index < currentStepIndex
                      ? 'bg-linear-purple w-6'
                      : index === currentStepIndex
                        ? 'bg-linear-purple w-8'
                        : 'bg-linear-border w-1.5',
                  )}
                />
              ))}
            </div>
          </div>
          <button
            onClick={handleExit}
            className="text-linear-text-secondary hover:text-linear-text -mr-2 p-2"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={currentStep}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
              transition={{ duration: 0.2 }}
              className="px-6 py-8"
            >
              {/* Step Content */}
              <MobileLogStepContent
                currentStep={currentStep}
                formData={formData}
                setFormData={setFormData}
                profile={profile}
                bodyComp={bodyComp}
                ffmiData={ffmiData}
                isUploadingPhoto={isUploadingPhoto}
                setShowWeightModal={setShowWeightModal}
                setShowBodyFatModal={setShowBodyFatModal}
                handlePhotoUpload={handlePhotoUpload}
                removePhoto={removePhoto}
              />{' '}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* Bottom Navigation */}
        <div className="border-linear-border bg-linear-bg border-t">
          <div className="flex gap-3 p-4">
            {currentStepIndex > 0 && (
              <Button
                variant="outline"
                onClick={handleBack}
                className="border-linear-border flex-1"
              >
                <ArrowLeft className="mr-2 h-4 w-4" />
                Back
              </Button>
            )}

            {currentStepIndex < STEPS.length - 1 ? (
              <Button
                onClick={handleNext}
                disabled={
                  (currentStep === 'weight' && !formData.weight) ||
                  (currentStep === 'measurements' &&
                    formData.method !== 'simple' &&
                    ((formData.method === 'navy' && (!formData.waist || !formData.neck)) ||
                      (formData.method === '3-site' &&
                        profile.gender === 'male' &&
                        (!formData.chest || !formData.abdominal || !formData.thigh))))
                }
                className={`bg-linear-purple hover:bg-linear-purple/90 flex-1 text-white transition-all ${
                  currentStep === 'weight' && formData.weight ? 'animate-glow-pulse' : ''
                }`}
              >
                Next
                <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            ) : (
              <Button
                onClick={handleSubmit}
                disabled={isSubmitting || !formData.weight}
                className="bg-linear-purple hover:bg-linear-purple/90 flex-1 text-white"
              >
                {isSubmitting ? (
                  <div className="h-4 w-4 animate-spin rounded-full border-b-2 border-white" />
                ) : (
                  <>
                    <Check className="mr-2 h-4 w-4" />
                    Save Entry
                  </>
                )}
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* Exit Confirmation Dialog */}
      <Dialog open={showExitDialog} onOpenChange={setShowExitDialog}>
        <DialogContent className="bg-linear-card border-linear-border mx-4 max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-linear-text">Discard changes?</DialogTitle>
          </DialogHeader>
          <p className="text-linear-text-secondary">
            You have unsaved data. Are you sure you want to exit?
          </p>
          <div className="mt-6 flex gap-3">
            <Button
              variant="outline"
              onClick={() => setShowExitDialog(false)}
              className="border-linear-border flex-1"
            >
              Keep Editing
            </Button>
            <Button
              onClick={() => router.push('/dashboard')}
              className="flex-1 bg-red-500 text-white hover:bg-red-600"
            >
              Discard
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Weight Modal */}
      <Dialog open={showWeightModal} onOpenChange={setShowWeightModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Weight</DialogTitle>
          </DialogHeader>
          {/* Direct input option for mobile */}
          <div className="mb-4">
            <Input
              type="number"
              inputMode="decimal"
              step="0.1"
              placeholder={`Enter weight in ${formData.weight_unit}`}
              value={formData.weight}
              onChange={(e) => setFormData((prev) => ({ ...prev, weight: e.target.value }))}
              className="bg-linear-bg border-linear-border h-14 text-center text-2xl font-bold"
              autoFocus
            />
          </div>
          <div className="text-linear-text-secondary mb-4 text-center text-sm">
            Or use the wheel picker below
          </div>
          <div className="py-8">
            <WeightWheelPicker
              weight={parseFloat(formData.weight) || 70}
              unit={formData.weight_unit}
              onWeightChange={(weight) => {
                setFormData((prev) => ({ ...prev, weight: weight.toFixed(1) }));
              }}
            />
          </div>
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setShowWeightModal(false)}
              className="border-linear-border flex-1"
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                setShowWeightModal(false);
              }}
              className="bg-linear-purple hover:bg-linear-purple/80 flex-1"
            >
              Save
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Body Fat Modal */}
      <Dialog open={showBodyFatModal} onOpenChange={setShowBodyFatModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Body Fat %</DialogTitle>
          </DialogHeader>
          <div className="py-8">
            <BodyFatWheelPicker
              bodyFat={formData.body_fat_percentage || 20}
              onBodyFatChange={(bf) => {
                setFormData((prev) => ({ ...prev, body_fat_percentage: bf }));
              }}
            />
          </div>
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setShowBodyFatModal(false)}
              className="border-linear-border flex-1"
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                setShowBodyFatModal(false);
              }}
              className="bg-linear-purple hover:bg-linear-purple/80 flex-1"
            >
              Save
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
