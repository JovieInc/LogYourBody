'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { WeightWheelPicker, BodyFatWheelPicker } from '@/components/ui/weight-wheel-picker';
import { toast } from '@/hooks/use-toast';
import { ArrowLeft, ArrowRight, CheckCircle, X } from 'lucide-react';
import Link from 'next/link';
import { format } from 'date-fns';
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
import { createClient } from '@/lib/supabase/client';
import { getProfile } from '@/lib/profile';
import dynamic from 'next/dynamic';
import { useMediaQuery } from '@/hooks/use-media-query';
// import { useSync } from '@/hooks/use-sync'
import { syncManager } from '@/lib/sync/sync-manager';
import { indexedDB } from '@/lib/db/indexed-db';
import { DesktopLogStepContent } from './DesktopLogStepContent';

const MobileLogPage = dynamic(() => import('./mobile-page'), { ssr: false });

type Step = 'weight' | 'method' | 'measurements' | 'photo' | 'review';

const STEPS: Step[] = ['weight', 'method', 'measurements', 'photo', 'review'];

const STEP_TITLES = {
  weight: 'Weight',
  method: 'Method',
  measurements: 'Measurements',
  photo: 'Photo',
  review: 'Review',
};

export default function LogWeightPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [currentStep, setCurrentStep] = useState<Step>('weight');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showWeightModal, setShowWeightModal] = useState(false);
  const [showBodyFatModal, setShowBodyFatModal] = useState(false);
  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false);

  // Form data
  const [formData, setFormData] = useState({
    weight: '',
    weight_unit: 'lbs' as 'kg' | 'lbs',
    method: 'simple' as 'simple' | 'navy' | '3-site' | '7-site',
    // Navy method
    waist: '',
    neck: '',
    hip: '', // for females
    // 3-site method
    chest: '',
    abdominal: '',
    thigh: '',
    tricep: '',
    suprailiac: '',
    // Calculated
    body_fat_percentage: null as number | null,
    notes: '',
    photo: null as File | null,
    photoPreview: null as string | null,
  });

  const [profile, setProfile] = useState<Partial<UserProfile>>({
    height: 71,
    height_unit: 'ft',
    gender: 'male',
    settings: {
      units: {
        weight: 'lbs',
        height: 'ft',
        measurements: 'in',
      },
    },
  });

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  // Load user profile
  useEffect(() => {
    if (user) {
      getProfile(user.id)
        .then((profileData) => {
          if (profileData) {
            setProfile({
              height: profileData.height,
              height_unit: profileData.height_unit,
              gender: profileData.gender,
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
  const progress = ((currentStepIndex + 1) / STEPS.length) * 100;

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

      setFormData((prev) => ({ ...prev, body_fat_percentage: bodyFat }));
    } catch (error) {
      console.error('Error calculating body fat:', error);
    }
  };

  const handleSubmit = async () => {
    if (!user) return;

    setIsSubmitting(true);
    try {
      const supabase = createClient();
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

      // Save body metrics through sync manager for offline support
      const metrics = await syncManager.logWeight(weightInKg, 'kg', formData.notes || undefined);

      // Also save to Supabase directly for immediate sync if online
      const { error } = await supabase.from('body_metrics').upsert({
        id: metrics.id,
        user_id: user.id,
        date: format(new Date(), 'yyyy-MM-dd'),
        weight: weightInKg,
        weight_unit: 'kg', // Always store in kg
        body_fat_percentage: formData.body_fat_percentage,
        body_fat_method: formData.method === 'simple' ? 'manual' : formData.method,
        waist: formData.waist ? parseFloat(formData.waist) : null,
        neck: formData.neck ? parseFloat(formData.neck) : null,
        hip: formData.hip ? parseFloat(formData.hip) : null,
        notes: formData.notes || null,
        photo_url: photoUrl,
        created_at: new Date(metrics.created_at).toISOString(),
        updated_at: new Date(metrics.updated_at).toISOString(),
      });

      // If online sync succeeded, mark as synced in IndexedDB
      if (!error) {
        await indexedDB.markAsSynced('bodyMetrics', metrics.id);
      }

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

      // Validate the file
      const validation = validateImageFile(file);
      if (!validation.valid) {
        toast({
          title: 'Invalid file',
          description: validation.error,
          variant: 'destructive',
        });
        return;
      }

      // Compress the image
      const compressedBlob = await compressImage(file, {
        maxWidth: 1920,
        maxHeight: 1920,
        quality: 0.85,
      });

      // Create compressed file
      const compressedFile = new File([compressedBlob], file.name, {
        type: compressedBlob.type,
        lastModified: Date.now(),
      });

      // Create preview URL
      const previewUrl = URL.createObjectURL(compressedFile);

      // Update form data
      setFormData((prev) => ({
        ...prev,
        photo: compressedFile,
        photoPreview: previewUrl,
      }));

      toast({
        title: 'Photo ready',
        description: 'Your photo has been processed and is ready to upload.',
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

  const isMobile = useMediaQuery('(max-width: 768px)');

  // Use mobile experience on small screens
  if (isMobile) {
    return <MobileLogPage />;
  }

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/dashboard">
                <Button variant="ghost" size="icon">
                  <X className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Log Metrics</h1>
            </div>
            <span className="text-linear-text-secondary text-sm">
              {format(new Date(), 'MMM d, yyyy')}
            </span>
          </div>
        </div>
      </header>

      {/* Progress Bar */}
      <div className="bg-linear-card border-linear-border border-b">
        <div className="container mx-auto px-4 py-3">
          <Progress value={progress} className="h-2" />
          <div className="mt-2 flex justify-between">
            {STEPS.map((step, index) => (
              <span
                key={step}
                className={`text-xs ${
                  index <= currentStepIndex
                    ? 'text-linear-text font-medium'
                    : 'text-linear-text-tertiary'
                }`}
              >
                {STEP_TITLES[step]}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="container mx-auto max-w-2xl px-4 py-6">
        <Card className="bg-linear-card border-linear-border">
          <DesktopLogStepContent
            currentStep={currentStep}
            setCurrentStep={setCurrentStep}
            formData={formData}
            setFormData={setFormData}
            profile={profile}
            bodyComp={bodyComp}
            ffmiData={ffmiData}
            isUploadingPhoto={isUploadingPhoto}
            setShowWeightModal={setShowWeightModal}
            handlePhotoUpload={handlePhotoUpload}
            removePhoto={removePhoto}
          />
          {/* Footer Actions */}
          <div className="border-linear-border flex justify-between border-t p-6">
            <Button variant="ghost" onClick={handleBack} disabled={currentStepIndex === 0}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back
            </Button>

            {currentStep === 'review' ? (
              <Button
                onClick={handleSubmit}
                disabled={isSubmitting || !formData.weight}
                className="bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                {isSubmitting ? (
                  <>
                    <CheckCircle className="mr-2 h-4 w-4 animate-pulse" />
                    Saving...
                  </>
                ) : (
                  <>
                    <CheckCircle className="mr-2 h-4 w-4" />
                    Save Entry
                  </>
                )}
              </Button>
            ) : (
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
                className={`bg-linear-purple hover:bg-linear-purple/80 text-white transition-all ${
                  currentStep === 'weight' && formData.weight && !isSubmitting
                    ? 'animate-glow-pulse'
                    : ''
                }`}
              >
                Next
                <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            )}
          </div>
        </Card>
      </main>

      {/* Weight Modal */}
      <Dialog open={showWeightModal} onOpenChange={setShowWeightModal}>
        <DialogContent className="bg-linear-card border-linear-border max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text text-center">Set Weight</DialogTitle>
          </DialogHeader>
          {/* Direct input option */}
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
                if (currentStep === 'weight' && formData.weight) {
                  setCurrentStep('method');
                }
              }}
              className="bg-linear-purple hover:bg-linear-purple/80 flex-1"
              disabled={!formData.weight}
            >
              Continue
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
    </div>
  );
}
