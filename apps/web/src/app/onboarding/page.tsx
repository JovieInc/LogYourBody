'use client';

import { useEffect } from 'react';
import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { OnboardingProvider, useOnboarding } from '@/contexts/OnboardingContext';
import { WelcomeStep } from './components/WelcomeStep';
import { DexaUploadStep } from './components/DexaUploadStep';
import { DataConfirmationStep } from './components/DataConfirmationStep';
import { MultiScanConfirmationStep } from './components/MultiScanConfirmationStep';
import { ProfileSetupStepV2 } from './components/ProfileSetupStepV2';
import { NotificationsStep } from './components/NotificationsStep';
import { CompletionStep } from './components/CompletionStep';
import { Progress } from '@/components/ui/progress';
import { Loader2 } from 'lucide-react';

function OnboardingFlow() {
  const { currentStep, totalSteps, data } = useOnboarding();
  const progress = (currentStep / totalSteps) * 100;

  const renderStep = () => {
    switch (currentStep) {
      case 1:
        return <WelcomeStep />;
      case 2:
        return <DexaUploadStep />;
      case 3:
        // Show multi-scan confirmation if we have multiple scans
        if (data.extractedScans && data.extractedScans.length > 1) {
          return <MultiScanConfirmationStep />;
        }
        return <DataConfirmationStep />;
      case 4:
        return <ProfileSetupStepV2 />;
      case 5:
        return <NotificationsStep />;
      case 6:
        return <CompletionStep />;
      default:
        return <WelcomeStep />;
    }
  };

  return (
    <div className="bg-linear-bg flex min-h-screen flex-col">
      {/* Progress bar */}
      <div className="w-full px-4 pb-4 pt-8">
        <Progress value={progress} className="mx-auto h-1 max-w-2xl" />
      </div>

      {/* Step content - with max height and scroll */}
      <div className="flex flex-1 items-center justify-center overflow-y-auto px-4 pb-8">
        <div className="w-full max-w-lg py-4">{renderStep()}</div>
      </div>
    </div>
  );
}

export default function OnboardingPage() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <OnboardingProvider>
      <OnboardingFlow />
    </OnboardingProvider>
  );
}
