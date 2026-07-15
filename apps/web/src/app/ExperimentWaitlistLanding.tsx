'use client';

import Image from 'next/image';
import { motion, useReducedMotion } from 'framer-motion';
import { useEffect, useRef, useState } from 'react';
import { analytics } from '@/lib/analytics';
import { cn } from '@/lib/utils';
import {
  buildLandingSource,
  LANDING_BRAND_ASSET,
  LANDING_PRODUCT_PROOF,
  type LandingAssignmentSource,
  type LandingVariant,
} from '@/lib/marketing/landing-registry';
import { waitlistLandingCopy } from './waitlist-copy';

type SubmitState = 'idle' | 'submitting' | 'success' | 'duplicate' | 'error';

export interface ExperimentWaitlistLandingProps {
  variant: LandingVariant;
  assignmentSource: LandingAssignmentSource;
}

export function ExperimentWaitlistLanding({
  variant,
  assignmentSource,
}: ExperimentWaitlistLandingProps) {
  const [email, setEmail] = useState('');
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [fieldError, setFieldError] = useState<string | null>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const reduceMotion = useReducedMotion();
  const source = buildLandingSource({
    audience: variant.audience,
    goal: variant.goal,
    assignmentSource,
  });

  useEffect(() => {
    analytics.track('web_landing_viewed', {
      variant: 'waitlist_editorial_v2',
      audience: variant.audience,
      goal: variant.goal,
      assignment_source: assignmentSource,
    });
  }, [assignmentSource, variant.audience, variant.goal]);

  useEffect(() => {
    if (fieldError) emailInputRef.current?.focus();
  }, [fieldError]);

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
    if (!trimmed || !emailInputRef.current?.checkValidity()) {
      setFieldError(waitlistLandingCopy.invalidEmailMessage);
      return;
    }

    setSubmitState('submitting');

    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: trimmed, source }),
      });
      const payload = (await response.json()) as {
        success?: boolean;
        status?: 'created' | 'existing';
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
        variant: 'waitlist_editorial_v2',
        audience: variant.audience,
        goal: variant.goal,
        assignment_source: assignmentSource,
        status: payload.status,
      });
      setSubmitState(payload.status === 'existing' ? 'duplicate' : 'success');
    } catch {
      setSubmitState('error');
    }
  }

  const motionTransition = { duration: reduceMotion ? 0 : 0.42 };

  return (
    <div
      className="font-inter min-h-[100svh] overflow-x-hidden bg-black text-[#F7F8F8]"
      data-testid="landing-experiment-v2"
      data-audience={variant.audience}
      data-goal={variant.goal}
    >
      <div className="relative isolate min-h-[100svh] overflow-hidden">
        <motion.div
          className="absolute inset-0 z-0 hidden lg:block"
          initial={reduceMotion ? false : { opacity: 0, scale: 1.025 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={reduceMotion ? { duration: 0 } : { duration: 0.7, ease: 'easeOut' }}
        >
          <Image
            src={variant.heroImage}
            alt={variant.heroAlt}
            fill
            priority
            sizes="(min-width: 1024px) 55vw, 100vw"
            className="object-cover object-center"
          />
        </motion.div>
        <div className="absolute inset-0 z-[1] hidden bg-[linear-gradient(90deg,#000_0%,#000_43%,rgba(0,0,0,0.94)_54%,rgba(0,0,0,0.08)_78%)] lg:block" />

        <header className="relative z-10 mx-auto flex w-full max-w-[1440px] items-center px-6 pb-5 pt-7 sm:px-8 lg:px-16 lg:pb-0 lg:pt-12">
          <div className="flex items-center gap-3" aria-label="LogYourBody">
            <Image
              src={LANDING_BRAND_ASSET.src}
              alt={LANDING_BRAND_ASSET.alt}
              width={LANDING_BRAND_ASSET.width}
              height={LANDING_BRAND_ASSET.height}
              className="h-11 w-11 rounded-[13px] sm:h-12 sm:w-12"
              priority
            />
            <span className="text-xl font-medium tracking-[-0.025em] sm:text-2xl">LogYourBody</span>
          </div>
        </header>

        <main
          id="main-content"
          className="relative z-10 mx-auto grid w-full max-w-[1440px] px-6 pb-14 sm:px-8 lg:min-h-[calc(100svh-96px)] lg:grid-cols-[minmax(0,0.98fr)_minmax(420px,1.02fr)] lg:items-center lg:px-16 lg:pb-12"
          tabIndex={-1}
        >
          <motion.section
            className="min-w-0 max-w-[650px] pt-5 lg:pb-16 lg:pt-0"
            aria-labelledby="landing-heading"
            initial={reduceMotion ? false : { opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={motionTransition}
          >
            <h1
              id="landing-heading"
              className="max-w-[12ch] text-balance text-[clamp(2.85rem,12vw,4rem)] font-semibold leading-[0.98] tracking-[-0.055em] lg:max-w-[10ch] lg:text-[clamp(4.5rem,5.6vw,5.8rem)]"
            >
              {variant.headline}
            </h1>
            <p className="mt-6 max-w-[590px] text-lg leading-7 tracking-[-0.015em] text-[#9CA0A8] sm:text-xl sm:leading-8 lg:mt-7 lg:text-2xl lg:leading-9">
              {variant.subheading}
            </p>

            <form
              className="mt-8 grid w-full max-w-[680px] gap-3 lg:mt-9 lg:grid-cols-[minmax(0,1fr)_auto]"
              onSubmit={handleSubmit}
              noValidate
              data-testid="landing-capture-form"
            >
              <label className="sr-only" htmlFor="waitlist-email-v2">
                {waitlistLandingCopy.emailLabel}
              </label>
              <input
                ref={emailInputRef}
                id="waitlist-email-v2"
                name="email"
                type="email"
                autoComplete="email"
                inputMode="email"
                placeholder="Email address"
                value={email}
                onChange={(event) => {
                  setEmail(event.target.value);
                  if (fieldError) setFieldError(null);
                  if (submitState === 'error') setSubmitState('idle');
                }}
                disabled={submitState === 'submitting' || submitState === 'success'}
                aria-invalid={Boolean(fieldError)}
                aria-describedby="waitlist-status-v2"
                className="min-h-[54px] w-full rounded-full border border-[#2A2C30] bg-black/65 px-6 text-base text-white outline-none backdrop-blur-xl transition-colors placeholder:text-[#6E7178] hover:border-[#45484F] focus:border-[#F7F8F8]/65 focus:ring-2 focus:ring-[#2563FF]/35 disabled:opacity-60 lg:min-h-[58px]"
              />
              <button
                type="submit"
                disabled={submitState === 'submitting' || submitState === 'success'}
                className="inline-flex min-h-[54px] w-full items-center justify-center rounded-full bg-[#F7F8F8] px-8 text-base font-semibold text-black transition-[background-color,transform] hover:bg-white focus:outline-none focus:ring-2 focus:ring-[#2563FF] focus:ring-offset-2 focus:ring-offset-black active:scale-[0.985] disabled:cursor-not-allowed disabled:opacity-60 lg:min-h-[58px] lg:w-auto lg:min-w-[230px]"
              >
                {submitState === 'submitting' ? 'Joining…' : 'Get early access'}
              </button>
              <div id="waitlist-status-v2" className="min-h-6 lg:col-span-2" aria-live="polite">
                {fieldError ? (
                  <p className="text-sm text-rose-300" role="alert">
                    {fieldError}
                  </p>
                ) : statusMessage ? (
                  <p
                    className={cn(
                      'text-sm',
                      submitState === 'error' ? 'text-rose-300' : 'text-emerald-300',
                    )}
                    role="status"
                  >
                    {statusMessage}
                  </p>
                ) : (
                  <p className="text-sm text-[#6E7178]">Private iPhone beta. No spam.</p>
                )}
              </div>
            </form>

            <p className="mt-9 hidden text-lg tracking-[-0.02em] text-[#F7F8F8] sm:text-xl lg:block lg:text-2xl">
              <span>One timeline.</span>{' '}
              <span className="text-[#9CA0A8]">The signal, without the noise.</span>
            </p>
          </motion.section>

          <motion.section
            className="relative mt-6 h-[390px] min-w-0 overflow-hidden rounded-t-[22px] border border-b-0 border-[#2A2C30] bg-[#0B0B0B] shadow-[0_-24px_80px_rgba(0,0,0,0.5)] lg:mb-[-10rem] lg:ml-auto lg:mt-auto lg:h-[520px] lg:w-[400px] lg:rounded-[22px] lg:border-b"
            aria-label="Current LogYourBody iPhone product capture"
            initial={reduceMotion ? false : { opacity: 0, y: 28 }}
            animate={{ opacity: 1, y: 0 }}
            transition={
              reduceMotion ? { duration: 0 } : { delay: 0.18, duration: 0.52, ease: 'easeOut' }
            }
            data-testid="landing-product-proof"
          >
            <Image
              src={LANDING_PRODUCT_PROOF.src}
              alt={LANDING_PRODUCT_PROOF.alt}
              width={LANDING_PRODUCT_PROOF.width}
              height={LANDING_PRODUCT_PROOF.height}
              sizes="(min-width: 1024px) 400px, calc(100vw - 48px)"
              className="h-auto w-full"
              priority
            />
            <div className="pointer-events-none absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-[#0B0B0B] to-transparent" />
          </motion.section>
          <p className="mx-auto mt-6 text-center text-lg tracking-[-0.02em] text-[#F7F8F8] sm:text-xl lg:hidden">
            <span>One timeline.</span>{' '}
            <span className="text-[#9CA0A8]">The signal, without the noise.</span>
          </p>
        </main>
      </div>
    </div>
  );
}
