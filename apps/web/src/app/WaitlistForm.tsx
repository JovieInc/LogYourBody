'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import { analytics } from '@/lib/analytics';
import { cn } from '@/lib/utils';
import { waitlistLandingCopy } from './waitlist-copy';

type SubmitState = 'idle' | 'submitting' | 'success' | 'error';

function landingAttribution() {
  if (typeof window === 'undefined') {
    return { source: 'landing:minimal:direct', campaign: 'direct' };
  }

  const params = new URLSearchParams(window.location.search);
  const campaign = params
    .get('utm_source')
    ?.toLowerCase()
    .replace(/[^a-z0-9_-]/g, '')
    .slice(0, 60);

  return {
    source: `landing:minimal:${campaign || 'direct'}`,
    campaign: campaign || 'direct',
  };
}

export function WaitlistForm() {
  const [email, setEmail] = useState('');
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [fieldError, setFieldError] = useState<string | null>(null);
  const started = useRef(false);

  useEffect(() => {
    const { campaign } = landingAttribution();
    analytics.track('web_landing_viewed', {
      landing_id: 'minimal_waitlist_v1',
      variant: 'waitlist_minimal',
      campaign,
    });
  }, []);

  function trackStart() {
    if (started.current) return;
    started.current = true;
    analytics.track('web_waitlist_started', {
      landing_id: 'minimal_waitlist_v1',
      variant: 'waitlist_minimal',
      campaign: landingAttribution().campaign,
    });
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFieldError(null);

    const trimmed = email.trim();
    if (!trimmed) {
      setFieldError(waitlistLandingCopy.invalidEmailMessage);
      analytics.track('web_waitlist_submit_result', { outcome: 'invalid' });
      return;
    }

    setSubmitState('submitting');
    const attribution = landingAttribution();
    analytics.track('web_waitlist_submit_attempted', {
      landing_id: 'minimal_waitlist_v1',
      variant: 'waitlist_minimal',
      campaign: attribution.campaign,
    });

    const form = event.currentTarget;
    const website = new FormData(form).get('website');

    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: trimmed, source: attribution.source, website }),
      });

      const payload = (await response.json()) as { success?: boolean };
      if (!response.ok || !payload.success) {
        if (response.status === 400) {
          setFieldError(waitlistLandingCopy.invalidEmailMessage);
          setSubmitState('idle');
          analytics.track('web_waitlist_submit_result', { outcome: 'invalid' });
          return;
        }
        setSubmitState('error');
        analytics.track('web_waitlist_submit_result', {
          outcome: response.status === 429 ? 'rate_limited' : 'server_error',
        });
        return;
      }

      analytics.track('web_waitlist_submitted', {
        landing_id: 'minimal_waitlist_v1',
        variant: 'waitlist_minimal',
        campaign: attribution.campaign,
      });
      analytics.track('web_waitlist_submit_result', { outcome: 'accepted' });
      setSubmitState('success');
    } catch {
      setSubmitState('error');
      analytics.track('web_waitlist_submit_result', { outcome: 'server_error' });
    }
  }

  return (
    <div className="mt-8 w-full max-w-xl">
      <form
        className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]"
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
          onFocus={trackStart}
          onChange={(event) => {
            setEmail(event.target.value);
            if (fieldError) setFieldError(null);
            if (submitState === 'error') setSubmitState('idle');
          }}
          disabled={submitState === 'submitting' || submitState === 'success'}
          aria-invalid={Boolean(fieldError)}
          aria-describedby="waitlist-status waitlist-consent"
          className="min-h-14 w-full rounded-full border border-white/15 bg-black/45 px-6 text-base text-white outline-none backdrop-blur-xl transition-colors placeholder:text-white/35 hover:border-white/25 focus:border-white/50 focus:ring-2 focus:ring-sky-400/30 disabled:opacity-60"
        />
        <div className="pointer-events-none absolute -left-[10000px]" aria-hidden="true">
          <label htmlFor="waitlist-website">Website</label>
          <input
            id="waitlist-website"
            name="website"
            type="text"
            tabIndex={-1}
            autoComplete="off"
          />
        </div>
        <button
          type="submit"
          disabled={submitState === 'submitting' || submitState === 'success'}
          className="inline-flex min-h-14 items-center justify-center rounded-full bg-white px-8 text-base font-semibold text-black transition-[background-color,transform] hover:bg-white/90 focus:outline-none focus:ring-2 focus:ring-white/50 focus:ring-offset-2 focus:ring-offset-black active:scale-[0.985] disabled:cursor-not-allowed disabled:opacity-60"
        >
          {submitState === 'submitting' ? 'Joining…' : waitlistLandingCopy.submitLabel}
        </button>
      </form>

      <div id="waitlist-status" className="mt-3 min-h-6" aria-live="polite">
        {fieldError ? (
          <p className="text-sm text-rose-300" role="alert">
            {fieldError}
          </p>
        ) : submitState === 'success' || submitState === 'error' ? (
          <p
            className={cn(
              'text-sm',
              submitState === 'error' ? 'text-rose-300' : 'text-emerald-300',
            )}
            role="status"
          >
            {submitState === 'success'
              ? waitlistLandingCopy.successMessage
              : waitlistLandingCopy.errorMessage}
          </p>
        ) : null}
      </div>

      <p id="waitlist-consent" className="mt-2 max-w-lg text-xs leading-5 text-white/45">
        Join to receive early-access and TestFlight invitations. Unsubscribe anytime. See our{' '}
        <Link
          href="/privacy"
          className="text-white/65 underline decoration-white/25 underline-offset-2 hover:text-white"
        >
          privacy policy
        </Link>
        .
      </p>
    </div>
  );
}
