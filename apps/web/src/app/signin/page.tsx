'use client';

import { BarChart3, AlertCircle } from 'lucide-react';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AuthSignIn } from '@/lib/ports/auth-ui';

export default function SignInPage() {
  const { exitReason } = useAuth();
  const showSessionExpired = exitReason === 'sessionExpired';
  return (
    <div className="bg-linear-bg flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mb-4 flex items-center justify-center">
            <BarChart3 className="text-linear-purple h-12 w-12" />
          </div>
          <h1 className="text-linear-text mb-2 text-3xl font-bold">Welcome back</h1>
          <p className="text-linear-text-secondary">Sign in to continue your fitness journey</p>
        </div>

        {showSessionExpired && (
          <div className="mb-4">
            <Alert className="border-yellow-500/40 bg-yellow-500/10 text-yellow-100">
              <AlertCircle className="mr-2 h-4 w-4" />
              <AlertDescription>
                <p className="font-medium">Session expired</p>
                <p className="text-sm text-yellow-100/80">
                  Your session ended. Please sign in again to continue.
                </p>
              </AlertDescription>
            </Alert>
          </div>
        )}

        <AuthSignIn />
      </div>
    </div>
  );
}
