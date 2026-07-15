import Image from 'next/image';
import Link from 'next/link';
import { MarketingFooter } from '@/components/MarketingFooter';
import { APP_CONFIG } from '@/constants/app';
import { LANDING_BRAND_ASSET, LANDING_PRODUCT_PROOF } from '@/lib/marketing/landing-registry';
import { WaitlistForm } from './WaitlistForm';
import { waitlistLandingCopy } from './waitlist-copy';

/** Stable waitlist surface retained as the rollback path for the art-direction gate. */
export function LegacyMinimalWaitlistLanding() {
  return (
    <div className="min-h-screen overflow-x-hidden bg-[#06070a] text-[#f7f8f8]">
      <a
        href="#main-content"
        className="sr-only z-50 rounded bg-white px-4 py-2 text-black focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
      >
        Skip to content
      </a>

      <header className="mx-auto flex h-20 w-full max-w-7xl items-center px-5 sm:px-8">
        <Link
          href="/"
          className="inline-flex items-center gap-3 rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/25"
        >
          <Image
            src={LANDING_BRAND_ASSET.src}
            alt=""
            width={LANDING_BRAND_ASSET.width}
            height={LANDING_BRAND_ASSET.height}
            className="h-9 w-9 rounded-[11px]"
            priority
          />
          <span className="text-base font-medium tracking-[-0.025em]">{APP_CONFIG.appName}</span>
        </Link>
      </header>

      <main id="main-content" tabIndex={-1}>
        <section
          className="relative isolate border-b border-white/[0.07]"
          aria-labelledby="legacy-landing-heading"
        >
          <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(circle_at_72%_45%,rgba(48,91,167,0.14),transparent_36%)]" />
          <div className="mx-auto grid min-h-[calc(100svh-5rem)] w-full max-w-7xl items-center gap-12 px-5 pb-16 pt-8 sm:px-8 lg:grid-cols-[minmax(0,1.06fr)_minmax(340px,0.62fr)] lg:gap-20 lg:pb-20 lg:pt-12">
            <div className="max-w-3xl">
              <p className="mb-5 text-sm font-medium tracking-[-0.01em] text-sky-300">
                Private iPhone beta
              </p>
              <h1
                id="legacy-landing-heading"
                className="max-w-[11ch] text-balance text-[clamp(3.15rem,8vw,6.4rem)] font-semibold leading-[0.94] tracking-[-0.06em]"
              >
                {waitlistLandingCopy.headline}
              </h1>
              <p className="mt-7 max-w-2xl text-pretty text-lg leading-8 tracking-[-0.015em] text-white/60 sm:text-xl sm:leading-9">
                {waitlistLandingCopy.subheading}
              </p>
              <WaitlistForm />
            </div>

            <div
              className="relative mx-auto h-[430px] w-full max-w-[390px] overflow-hidden rounded-[2.2rem] border border-white/10 bg-black shadow-[0_28px_90px_rgba(0,0,0,0.55)] lg:h-[590px]"
              aria-label="LogYourBody product preview"
              data-testid="landing-product-proof"
            >
              <Image
                src={LANDING_PRODUCT_PROOF.src}
                alt={LANDING_PRODUCT_PROOF.alt}
                width={LANDING_PRODUCT_PROOF.width}
                height={LANDING_PRODUCT_PROOF.height}
                sizes="(min-width: 1024px) 390px, calc(100vw - 40px)"
                className="h-auto w-full"
                priority
              />
              <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-black to-transparent" />
            </div>
          </div>
        </section>
      </main>

      <MarketingFooter />
    </div>
  );
}
