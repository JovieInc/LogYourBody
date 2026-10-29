'use client';

import { useEffect, useRef, useState } from 'react';
import { Button } from '@jovie/ui/atoms/button';
import { Input } from '@jovie/ui/atoms/input';
import { analytics, type AnalyticsProperties } from '@/lib/analytics';
import {
  waitlistCampaign,
  type WaitlistLandingId,
  type WaitlistVariant,
} from '@/lib/analytics-schema';
import { cn } from '@/lib/utils';
import { waitlistLandingCopy } from './waitlist-copy';

type SubmitState = 'idle' | 'submitting' | 'success' | 'error';

function landingAttribution() {
  if (typeof window === 'undefined') {
    return { source: 'landing:minimal:direct', campaign: 'direct' as const };
  }

  const params = new URLSearchParams(window.location.search);
  const campaign = waitlistCampaign(params.get('utm_source'));

  return {
    source: `landing:minimal:${campaign}`,
    campaign,
  };
}

export interface WaitlistFormProps {
  /** The landing that renders this form; recorded on every funnel event. */
  landingId: WaitlistLandingId;
  variant: WaitlistVariant;
}

export function WaitlistForm({ landingId, variant }: WaitlistFormProps) {
  const [email, setEmail] = useState('');
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [fieldError, setFieldError] = useState<string | null>(null);
  const started = useRef(false);

  useEffect(() => {
    const { campaign } = landingAttribution();
    analytics.track('web_landing_viewed', {
      landing_id: landingId,
      variant,
      campaign,
    });
  }, [landingId, variant]);

  function trackStart() {
    if (started.current) return;
    started.current = true;
    analytics.track('web_waitlist_started', {
      landing_id: landingId,
      variant,
      campaign: landingAttribution().campaign,
    });
  }

  function trackResult(outcome: NonNullable<AnalyticsProperties['outcome']>) {
    analytics.track('web_waitlist_submit_result', {
      landing_id: landingId,
      variant,
      campaign: landingAttribution().campaign,
      outcome,
    });
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFieldError(null);

    const trimmed = email.trim();
    if (!trimmed) {
      setFieldError(waitlistLandingCopy.invalidEmailMessage);
      trackResult('invalid');
      return;
    }

    setSubmitState('submitting');
    const attribution = landingAttribution();
    analytics.track('web_waitlist_submit_attempted', {
      landing_id: landingId,
      variant,
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
          trackResult('invalid');
          return;
        }
        setSubmitState('error');
        trackResult(response.status === 429 ? 'rate_limited' : 'server_error');
        return;
      }

      // Acceptance intentionally includes duplicates and honeypots. Durable
      // registration counts come only from the server-owned waitlist store.
      analytics.track('web_waitlist_submitted', {
        landing_id: landingId,
        variant,
        campaign: attribution.campaign,
      });
      trackResult('accepted');
      setSubmitState('success');
    } catch {
      setSubmitState('error');
      trackResult('server_error');
    }
  }

  return (
    <div className="lyb-marketing w-full max-w-[640px]">
      <form className="flex flex-wrap items-center gap-3" onSubmit={handleSubmit} noValidate>
        <label className="sr-only" htmlFor="waitlist-email">
          {waitlistLandingCopy.emailLabel}
        </label>
        <div className="min-w-0 flex-1 basis-48">
          <Input
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
            inputSize="lg"
            className="h-11 text-base"
          />
        </div>
        <div className="pointer-events-none sr-only" aria-hidden="true">
          <label htmlFor="waitlist-website">Website</label>
          <input
            id="waitlist-website"
            name="website"
            type="text"
            tabIndex={-1}
            autoComplete="off"
          />
        </div>
        <Button
          type="submit"
          aria-label={waitlistLandingCopy.submitLabel}
          size="marketing"
          loading={submitState === 'submitting'}
          disabled={submitState === 'submitting' || submitState === 'success'}
          className="my-2 w-full min-w-44 sm:w-auto"
        >
          {waitlistLandingCopy.submitLabel}
        </Button>
      </form>

      <div id="waitlist-status" className="mt-2 min-h-16 sm:mt-3" aria-live="polite">
        {fieldError ? (
          <p className="text-primary-token text-sm" role="alert">
            {fieldError}
          </p>
        ) : submitState === 'success' || submitState === 'error' ? (
          <p
            className={cn(
              'text-sm',
              submitState === 'error' ? 'text-primary-token' : 'text-secondary-token',
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
