import { BarChart3 } from 'lucide-react';
import { AuthSignUp } from '@/lib/ports/auth-ui';

export default function SignupPage() {
  return (
    <div className="bg-linear-bg flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mb-4 flex items-center justify-center">
            <BarChart3 className="text-linear-purple h-12 w-12" />
          </div>
          <h1 className="text-linear-text mb-2 text-3xl font-bold">Create your account</h1>
          <p className="text-linear-text-secondary">Start tracking your fitness journey today</p>
        </div>

        <AuthSignUp />
      </div>
    </div>
  );
}
