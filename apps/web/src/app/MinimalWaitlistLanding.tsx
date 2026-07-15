import Image from 'next/image';
import Link from 'next/link';
import { MarketingFooter } from '@/components/MarketingFooter';
import { APP_CONFIG } from '@/constants/app';
import {
  LANDING_BRAND_ASSET,
  LANDING_MEDIA,
  LANDING_PRODUCT_PROOF,
} from '@/lib/marketing/landing-registry';
import styles from './MinimalWaitlistLanding.module.css';
import { WaitlistForm } from './WaitlistForm';
import { waitlistLandingCopy } from './waitlist-copy';

const signals = [
  { index: '01', label: 'Weight', detail: 'The daily measure' },
  { index: '02', label: 'Body fat', detail: 'The composition estimate' },
  { index: '03', label: 'Lean mass', detail: 'The derived estimate' },
  { index: '04', label: 'Photos', detail: 'The visual record' },
] as const;

function BrandMark() {
  return (
    <Link
      href="/"
      aria-label={`${APP_CONFIG.appName} home`}
      className="inline-flex items-center gap-3 rounded-full text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/40"
    >
      <Image
        src={LANDING_BRAND_ASSET.src}
        alt=""
        width={LANDING_BRAND_ASSET.width}
        height={LANDING_BRAND_ASSET.height}
        className="h-10 w-10 rounded-[12px] shadow-[0_10px_35px_rgba(0,0,0,0.35)] sm:h-11 sm:w-11"
        priority
      />
      <span className="text-lg font-semibold tracking-[-0.035em] sm:text-xl">
        {APP_CONFIG.appName}
      </span>
    </Link>
  );
}

export function MinimalWaitlistLanding() {
  return (
    <div className="min-h-screen overflow-x-hidden bg-[#050608] text-[#f5f7f7]">
      <a
        href="#main-content"
        className="sr-only z-50 rounded-full bg-white px-4 py-2 text-black focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
      >
        Skip to content
      </a>

      <header className="pointer-events-none absolute inset-x-0 top-0 z-30">
        <div className="mx-auto flex h-20 w-full max-w-[1480px] items-center justify-between px-5 sm:h-24 sm:px-8 lg:px-12">
          <div className="pointer-events-auto">
            <BrandMark />
          </div>
          <span className="hidden text-[11px] font-medium uppercase tracking-[0.18em] text-white/55 sm:block">
            Private iPhone beta
          </span>
        </div>
      </header>

      <main id="main-content" tabIndex={-1}>
        <section
          className="relative isolate flex min-h-[100svh] items-end overflow-hidden border-b border-white/[0.08]"
          aria-labelledby="landing-heading"
        >
          <div className={`${styles.heroImage} absolute inset-0 -z-20`} aria-hidden="true">
            <Image
              src={LANDING_MEDIA.men.src}
              alt=""
              fill
              priority
              sizes="100vw"
              className="object-cover object-[64%_center] sm:object-[68%_center] lg:object-center"
            />
          </div>
          <div className="absolute inset-0 -z-10 bg-[linear-gradient(90deg,rgba(3,4,6,0.98)_0%,rgba(3,4,6,0.9)_35%,rgba(3,4,6,0.34)_67%,rgba(3,4,6,0.14)_100%)] max-lg:bg-[linear-gradient(180deg,rgba(3,4,6,0.42)_0%,rgba(3,4,6,0.22)_26%,rgba(3,4,6,0.93)_72%,#030406_100%)]" />
          <div className="pointer-events-none absolute inset-x-0 bottom-0 -z-10 h-40 bg-gradient-to-t from-[#050608] to-transparent" />

          <div className="mx-auto w-full max-w-[1480px] px-5 pb-6 pt-24 sm:px-8 sm:pb-16 sm:pt-32 lg:px-12 lg:pb-[8vh]">
            <div className="max-w-[760px]">
              <p
                className={`${styles.heroEyebrow} text-xs font-medium uppercase tracking-[0.2em] text-white/65`}
              >
                Body composition, in context
              </p>
              <h1
                id="landing-heading"
                className={`${styles.heroTitle} mt-4 max-w-[10.5ch] text-balance text-[clamp(3.25rem,9.5vw,8.5rem)] font-semibold leading-[0.88] tracking-[-0.07em] sm:mt-5`}
              >
                {waitlistLandingCopy.headline}
              </h1>
              <p
                className={`${styles.heroBody} text-white/66 mt-5 max-w-[620px] text-pretty text-base leading-7 tracking-[-0.02em] sm:mt-7 sm:text-xl sm:leading-9`}
              >
                {waitlistLandingCopy.subheading}
              </p>
              <div id="early-access" className={styles.heroForm}>
                <WaitlistForm />
              </div>
            </div>
          </div>

          <div
            aria-hidden="true"
            className="absolute bottom-8 right-8 hidden items-center gap-3 text-[10px] font-medium uppercase tracking-[0.18em] text-white/45 lg:flex"
          >
            <span className="h-px w-10 bg-white/25" />
            Scroll to see the signal
          </div>
        </section>

        <section className="relative overflow-hidden border-b border-white/[0.08] px-5 py-24 sm:px-8 sm:py-32 lg:px-12 lg:py-44">
          <div aria-hidden="true" className={styles.ambientOrb} />
          <div className="mx-auto w-full max-w-[1380px]">
            <div className={`${styles.reveal} grid gap-10 lg:grid-cols-[0.85fr_1.15fr] lg:gap-24`}>
              <p className="pt-2 text-xs font-medium uppercase tracking-[0.2em] text-sky-300">
                The whole picture
              </p>
              <div>
                <h2 className="max-w-[13ch] text-balance text-[clamp(3rem,7vw,7rem)] font-medium leading-[0.94] tracking-[-0.065em]">
                  One number is a moment. The trend is the answer.
                </h2>
                <p className="mt-8 max-w-2xl text-pretty text-lg leading-8 text-white/55 sm:text-xl sm:leading-9">
                  See the measures you already care about on one timeline, so today never has to
                  explain everything.
                </p>
              </div>
            </div>

            <ol className={`${styles.reveal} mt-20 border-t border-white/[0.12] lg:mt-32`}>
              {signals.map((signal) => (
                <li
                  key={signal.label}
                  className="group grid gap-2 border-b border-white/[0.12] py-6 transition-colors hover:border-white/30 sm:grid-cols-[64px_1fr_auto] sm:items-baseline sm:gap-6 sm:py-7"
                >
                  <span className="text-xs tabular-nums text-white/30">{signal.index}</span>
                  <span className="text-[clamp(1.75rem,4vw,3.6rem)] font-medium tracking-[-0.045em] text-white/90 transition-transform duration-300 group-hover:translate-x-2">
                    {signal.label}
                  </span>
                  <span className="text-sm text-white/40 sm:text-base">{signal.detail}</span>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="relative border-b border-white/[0.08] bg-[#08090c] px-5 py-24 sm:px-8 sm:py-32 lg:px-12 lg:py-44">
          <div className="mx-auto grid w-full max-w-[1380px] gap-16 lg:grid-cols-[0.76fr_1.24fr] lg:items-start lg:gap-24">
            <div className="lg:sticky lg:top-28">
              <p className="text-xs font-medium uppercase tracking-[0.2em] text-sky-300">
                Built for the check-in
              </p>
              <h2 className="mt-6 max-w-[10ch] text-balance text-[clamp(3rem,6vw,6.5rem)] font-medium leading-[0.92] tracking-[-0.065em]">
                Your progress, in context.
              </h2>
              <p className="text-white/52 mt-7 max-w-md text-lg leading-8">
                Log a measurement. Keep the record. Come back to the trend—not the noise around a
                single day.
              </p>
              <div className="mt-12 flex items-center gap-4 text-sm text-white/50">
                <span className="h-2 w-2 rounded-full bg-emerald-400 shadow-[0_0_18px_rgba(52,211,153,0.7)]" />
                Real iPhone product capture
              </div>
            </div>

            <div className={`${styles.productReveal} relative mx-auto w-full max-w-[720px]`}>
              <div className="absolute -inset-x-8 top-[12%] h-[55%] rounded-full bg-sky-500/[0.08] blur-[90px]" />
              <div
                className="relative mx-auto max-h-[940px] w-full max-w-[570px] overflow-hidden rounded-[2.8rem] border border-white/[0.14] bg-black shadow-[0_50px_140px_rgba(0,0,0,0.75)]"
                aria-label="LogYourBody product preview"
                data-testid="landing-product-proof"
              >
                <Image
                  src={LANDING_PRODUCT_PROOF.src}
                  alt={LANDING_PRODUCT_PROOF.alt}
                  width={LANDING_PRODUCT_PROOF.width}
                  height={LANDING_PRODUCT_PROOF.height}
                  sizes="(min-width: 1024px) 570px, calc(100vw - 40px)"
                  className="h-auto w-full"
                />
                <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-black via-black/85 to-transparent" />
              </div>
            </div>
          </div>
        </section>

        <section className="relative isolate overflow-hidden px-5 py-32 text-center sm:px-8 sm:py-40 lg:py-52">
          <div aria-hidden="true" className={styles.finalGlow} />
          <svg
            aria-hidden="true"
            className={`${styles.finalArcs} pointer-events-none absolute inset-x-0 bottom-0 -z-10 h-[72%] w-full`}
            viewBox="0 0 1200 520"
            preserveAspectRatio="xMidYMax slice"
          >
            {[90, 170, 260, 360, 480, 620].map((radius, index) => (
              <ellipse
                key={radius}
                cx="600"
                cy="610"
                rx={radius}
                ry={220 - index * 8}
                fill="none"
                stroke={index % 2 === 0 ? 'rgba(125,190,255,.62)' : 'rgba(255,255,255,.28)'}
                strokeWidth={index < 2 ? 1.5 : 1}
              />
            ))}
          </svg>
          <div className={`${styles.reveal} mx-auto max-w-4xl`}>
            <p className="text-xs font-medium uppercase tracking-[0.2em] text-sky-300">
              TestFlight access
            </p>
            <h2 className="mt-6 text-balance text-[clamp(3.25rem,8vw,8rem)] font-medium leading-[0.9] tracking-[-0.07em]">
              See what the work is doing.
            </h2>
            <p className="mx-auto mt-7 max-w-xl text-lg leading-8 text-white/55 sm:text-xl">
              Join the waitlist. We’ll email you when a beta spot opens.
            </p>
            <a
              href="#early-access"
              className="mt-9 inline-flex min-h-14 items-center justify-center rounded-full bg-white px-9 text-base font-semibold text-black transition-[transform,background-color] duration-200 hover:-translate-y-0.5 hover:bg-sky-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-300 focus-visible:ring-offset-4 focus-visible:ring-offset-[#050608] active:translate-y-0"
            >
              Request early access
            </a>
          </div>
        </section>
      </main>

      <MarketingFooter />
    </div>
  );
}
