'use client';

import { useEffect, useState } from 'react';
import { APP_CONFIG } from '@/constants/app';
import { analytics } from '@/lib/analytics';
import { cn } from '@/lib/utils';
import { waitlistLandingCopy } from './waitlist-copy';

type SubmitState = 'idle' | 'submitting' | 'success' | 'duplicate' | 'error';

export function MinimalWaitlistLanding() {
  const [email, setEmail] = useState('');
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [fieldError, setFieldError] = useState<string | null>(null);

  useEffect(() => {
    analytics.track('web_landing_viewed', { variant: 'waitlist_minimal' });
  }, []);

  const statusMessage =
    submitState === 'success'
      ? waitlistLandingCopy.successMessage
      : submitState === 'duplicate'
        ? waitlistLandingCopy.duplicateMessage
        : submitState === 'error'
          ? waitlistLandingCopy.errorMessage
          : null;

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFieldError(null);

    const trimmed = email.trim();
    if (!trimmed) {
      setFieldError(waitlistLandingCopy.invalidEmailMessage);
      return;
    }

    setSubmitState('submitting');

    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: trimmed, source: 'landing' }),
      });

      const payload = (await response.json()) as {
        success?: boolean;
        status?: 'created' | 'existing';
        error?: string;
      };

      if (!response.ok || !payload.success) {
        if (response.status === 400) {
          setFieldError(waitlistLandingCopy.invalidEmailMessage);
          setSubmitState('idle');
          return;
        }
        setSubmitState('error');
        return;
      }

      analytics.track('web_waitlist_submitted', {
        variant: 'waitlist_minimal',
        status: payload.status,
      });

      setSubmitState(payload.status === 'existing' ? 'duplicate' : 'success');
    } catch {
      setSubmitState('error');
    }
  }

  return (
    <div className="font-inter flex min-h-screen flex-col bg-[#08090a] text-white">
      <header className="flex items-center justify-center px-6 py-8">
        <span className="text-sm font-semibold tracking-[0.18em] text-white/70">
          {APP_CONFIG.appName}
        </span>
      </header>

      <main
        id="main-content"
        className="flex flex-1 items-center justify-center px-6 pb-16"
        tabIndex={-1}
      >
        <div className="w-full max-w-xl text-center">
          <h1 className="text-4xl font-semibold leading-tight tracking-tight text-white sm:text-5xl md:text-6xl">
            {waitlistLandingCopy.headline}
          </h1>
          <p className="text-white/62 mx-auto mt-5 max-w-lg text-lg leading-8 sm:text-xl">
            {waitlistLandingCopy.subheading}
          </p>

          <form
            className="mx-auto mt-10 flex w-full max-w-md flex-col gap-3 sm:flex-row"
            onSubmit={handleSubmit}
            noValidate
          >
            <label className="sr-only" htmlFor="waitlist-email">
              {waitlistLandingCopy.emailLabel}
            </label>
            <input
              id="waitlist-email"
              name="email"
              type="email"
              autoComplete="email"
              inputMode="email"
              placeholder={waitlistLandingCopy.emailPlaceholder}
              value={email}
              onChange={(event) => {
                setEmail(event.target.value);
                if (fieldError) setFieldError(null);
                if (submitState === 'error') setSubmitState('idle');
              }}
              disabled={submitState === 'submitting' || submitState === 'success'}
              className="border-white/14 min-h-12 flex-1 rounded-full border bg-white/[0.04] px-5 text-base text-white outline-none transition placeholder:text-white/35 focus:border-white/30 focus:ring-2 focus:ring-white/15 disabled:opacity-60"
            />
            <button
              type="submit"
              disabled={submitState === 'submitting' || submitState === 'success'}
              className="hover:bg-white/88 inline-flex min-h-12 items-center justify-center rounded-full bg-white px-6 text-sm font-semibold text-black transition focus:outline-none focus:ring-2 focus:ring-white/40 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitState === 'submitting' ? 'Joining...' : waitlistLandingCopy.submitLabel}
            </button>
          </form>

          <div className="mt-4 min-h-6">
            {fieldError ? (
              <p className="text-sm text-rose-300" role="alert">
                {fieldError}
              </p>
            ) : null}
            {statusMessage ? (
              <p
                className={cn(
                  'text-sm',
                  submitState === 'error' ? 'text-rose-300' : 'text-emerald-300',
                )}
                role="status"
              >
                {statusMessage}
              </p>
            ) : null}
          </div>
        </div>
      </main>
    </div>
  );
}
