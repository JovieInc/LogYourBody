import Image from 'next/image';
import Link from 'next/link';
import { MarketingFooter } from '@/components/MarketingFooter';
import { APP_CONFIG } from '@/constants/app';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import styles from './LaunchLanding.module.css';
import { launchLandingCopy, launchLandingFeatures } from './launch-landing-copy';
import { WaitlistForm } from './WaitlistForm';

const HERO_IMAGE = '/marketing/landing/home-metric-first.png';

function BrandMark() {
  return (
    <Link href="/" className="inline-flex items-center gap-3" aria-label="LogYourBody home">
      <Image
        src="/brand/logyourbody-app-icon.png"
        alt=""
        width={28}
        height={28}
        className="rounded-[7px]"
        priority
      />
      <span className="text-[15px] font-medium tracking-[-0.01em]">LogYourBody</span>
    </Link>
  );
}

const HERO_ACTION_ID = 'early-access';

/**
 * One form on the page. The pricing section links back to it so the email
 * field is never duplicated (ids and autofill stay unique).
 */
function PrimaryAction({ id }: { id: string }) {
  if (LANDING_FLAGS.APP_STORE_LIVE) {
    return (
      <Link href={APP_CONFIG.appStoreUrl} className={styles.pill} data-testid={id}>
        {launchLandingCopy.appStoreCta}
      </Link>
    );
  }

  if (id !== HERO_ACTION_ID) {
    return (
      <a href={`#${HERO_ACTION_ID}`} className={styles.pill} data-testid={id}>
        {launchLandingCopy.waitlistCta}
      </a>
    );
  }

  return (
    <div id={HERO_ACTION_ID} data-testid={id} className="max-w-[440px] scroll-mt-24">
      <WaitlistForm />
    </div>
  );
}

export function LaunchLanding() {
  return (
    <div className={`${styles.page} lyb-landing min-h-screen overflow-x-hidden`}>
      <a
        href="#main-content"
        className="sr-only z-50 rounded-full bg-white px-4 py-2 text-black focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
      >
        Skip to content
      </a>

      <header className="mx-auto flex h-20 w-full max-w-[1200px] items-center justify-between px-5 sm:px-8">
        <BrandMark />
        <span className={`${styles.quiet} hidden text-[13px] sm:block`}>
          {launchLandingCopy.platformNote}
        </span>
      </header>

      <main id="main-content" tabIndex={-1}>
        <section
          aria-labelledby="landing-heading"
          className="mx-auto grid w-full max-w-[1200px] items-center gap-14 px-5 pb-20 pt-10 sm:px-8 sm:pt-16 lg:grid-cols-[1.05fr_0.95fr] lg:gap-20 lg:pb-32 lg:pt-20"
        >
          <div className={styles.rise}>
            <h1
              id="landing-heading"
              className={`${styles.display} max-w-[11ch] text-balance text-[clamp(2.75rem,7.5vw,5.5rem)]`}
            >
              {launchLandingCopy.headline}
            </h1>
            <p
              className={`${styles.secondary} mt-6 max-w-[34rem] text-pretty text-lg leading-8 sm:text-xl sm:leading-9`}
            >
              {launchLandingCopy.subheading}
            </p>
            <div className="mt-9">
              <PrimaryAction id={HERO_ACTION_ID} />
            </div>
          </div>

          <div className={`${styles.riseLate} mx-auto w-full max-w-[340px] lg:max-w-[360px]`}>
            <div className={styles.phone}>
              <Image
                src={HERO_IMAGE}
                alt={launchLandingCopy.heroImageAlt}
                width={780}
                height={1688}
                priority
                sizes="(min-width: 1024px) 360px, 340px"
                className="block h-auto w-full"
              />
            </div>
          </div>
        </section>

        <section
          aria-label="How it keeps the answer honest"
          className={`${styles.hairline} mx-auto w-full max-w-[1200px] border-t px-5 py-16 sm:px-8 lg:py-24`}
        >
          <ol className="grid gap-10 sm:grid-cols-3 sm:gap-8">
            {launchLandingCopy.signals.map((signal) => (
              <li key={signal.title} className="max-w-[30ch]">
                <h2 className="text-[19px] font-medium tracking-[-0.01em]">{signal.title}</h2>
                <p className={`${styles.secondary} mt-2 text-[15px] leading-6`}>{signal.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section
          aria-labelledby="features-heading"
          className={`${styles.hairline} mx-auto w-full max-w-[1200px] border-t px-5 py-16 sm:px-8 lg:py-24`}
        >
          <h2
            id="features-heading"
            className={`${styles.heading} text-[clamp(1.75rem,3.5vw,2.5rem)]`}
          >
            {launchLandingCopy.featuresHeading}
          </h2>
          <ul className={`${styles.hairlineStrong} mt-10 border-t`}>
            {launchLandingFeatures.map((feature) => (
              <li
                key={feature.id}
                className={`${styles.hairline} grid gap-1 border-b py-5 sm:grid-cols-[minmax(0,260px)_1fr] sm:gap-8 sm:py-6`}
              >
                <h3 className="text-[17px] font-medium tracking-[-0.01em]">{feature.name}</h3>
                <p className={`${styles.secondary} text-[16px] leading-7`}>{feature.description}</p>
              </li>
            ))}
          </ul>
        </section>

        <section
          aria-labelledby="pricing-heading"
          className={`${styles.hairline} mx-auto w-full max-w-[1200px] border-t px-5 py-16 sm:px-8 lg:py-24`}
        >
          <div className="max-w-[40rem]">
            <h2
              id="pricing-heading"
              className={`${styles.heading} text-[clamp(1.75rem,3.5vw,2.5rem)]`}
            >
              {launchLandingCopy.pricingHeading}
            </h2>
            <p className="mt-4 text-lg leading-8 sm:text-xl sm:leading-9">
              {launchLandingCopy.pricingLine}
            </p>
            <p className={`${styles.quiet} mt-2 text-[15px]`}>{launchLandingCopy.pricingNote}</p>
            <div className="mt-8">
              <PrimaryAction id="pricing-action" />
            </div>
          </div>
        </section>
      </main>

      <MarketingFooter />
    </div>
  );
}
