'use client';

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
    <div className="mt-6 w-full max-w-[640px] sm:mt-9">
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
          aria-describedby="waitlist-status"
          className="focus:ring-[var(--landing-accent,#11afff)]/50 min-h-11 w-full rounded-full border border-white/20 bg-black/55 px-5 text-sm text-white shadow-[0_18px_60px_rgba(0,0,0,0.22)] outline-none backdrop-blur-xl transition-[border-color,background-color,box-shadow] placeholder:text-white/60 hover:border-white/35 hover:bg-black/65 focus:border-white/60 focus:bg-black/70 focus:ring-2 disabled:opacity-60"
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
          className="group inline-flex min-h-11 items-center justify-center rounded-full p-1.5 text-sm font-[510] text-black outline-none disabled:cursor-not-allowed disabled:opacity-60 sm:min-w-52"
        >
          <span className="inline-flex h-8 w-full items-center justify-center rounded-full bg-white px-6 shadow-[0_18px_55px_rgba(0,0,0,0.24)] transition-[background-color,transform,box-shadow] group-hover:bg-sky-50 group-hover:shadow-[0_22px_65px_rgba(0,0,0,0.34)] group-focus-visible:ring-2 group-focus-visible:ring-[var(--landing-accent,#11afff)] group-focus-visible:ring-offset-2 group-focus-visible:ring-offset-black motion-safe:group-hover:-translate-y-0.5 motion-safe:group-active:translate-y-0 motion-safe:group-active:scale-[0.985]">
            {submitState === 'submitting' ? 'Joining…' : waitlistLandingCopy.submitLabel}
          </span>
        </button>
      </form>

      <div id="waitlist-status" className="mt-2 min-h-10 sm:mt-3" aria-live="polite">
        {fieldError ? (
          <p className="text-sm text-[var(--landing-error,#ff677d)]" role="alert">
            {fieldError}
          </p>
        ) : submitState === 'success' || submitState === 'error' ? (
          <p
            className={cn(
              'text-sm',
              submitState === 'error'
                ? 'text-[var(--landing-error,#ff677d)]'
                : 'text-[var(--landing-accent,#11afff)]',
            )}
            role="status"
          >
            {submitState === 'success'
              ? waitlistLandingCopy.successMessage
              : waitlistLandingCopy.errorMessage}
          </p>
        ) : null}
      </div>
    </div>
  );
}
