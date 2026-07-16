'use client';

import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { X, Mail } from 'lucide-react';

export function EmailConfirmationBanner() {
  const { user } = useAuth();
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    setIsVisible(user?.primaryEmailAddress?.verification?.status === 'unverified');
  }, [user]);

  if (!isVisible) return null;

  return (
    <div className="bg-linear-to-r fixed left-0 right-0 top-0 z-50 from-blue-600 to-blue-700 p-4 shadow-lg">
      <div className="mx-auto max-w-7xl">
        <Alert className="border-white/20 bg-white/10 text-white">
          <Mail className="h-4 w-4" />
          <AlertDescription className="flex items-center justify-between">
            <div className="mr-4 flex-1">
              <p className="font-medium">Verify your email address</p>
              <p className="mt-1 text-sm opacity-90">
                Please check your email and click the confirmation link to unlock all features.
                Verification emails are managed by Jovie. Use the link in your inbox to continue.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsVisible(false)}
                className="text-white/80 transition-colors hover:text-white"
                aria-label="Dismiss banner"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
          </AlertDescription>
        </Alert>
      </div>
    </div>
  );
}
