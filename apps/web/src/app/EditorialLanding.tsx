import Image from 'next/image';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { Button } from '@jovie/ui/atoms/button';
import { APP_CONFIG } from '@/constants/app';
import { LANDING_PRODUCT_PROOF } from '@/lib/marketing/landing-registry';
import { launchLandingCopy } from './launch-landing-copy';
import { WaitlistForm } from './WaitlistForm';
import styles from './EditorialLanding.module.css';
import foundation from './LaunchLanding.module.css';

const trend = [
  165, 160, 170, 152, 149, 154, 143, 137, 142, 132, 128, 131, 120, 115, 118, 111, 104, 109, 96, 93,
  99, 89, 84, 82, 77, 71, 76, 65, 60, 64,
];

function Chapter({ children }: { children: ReactNode }) {
  return <p className={styles.chapter}>{children}</p>;
}

function PrimaryAction({ appStoreLive }: { appStoreLive: boolean }) {
  return (
    <span className={styles.actionTarget}>
      <Button asChild size="marketing">
        <Link href={appStoreLive ? APP_CONFIG.appStoreUrl : '#early-access'}>
          {appStoreLive ? launchLandingCopy.appStoreCta : launchLandingCopy.waitlistCta}
        </Link>
      </Button>
    </span>
  );
}

function FeatureRows({ rows }: { rows: readonly { title: string; body: string }[] }) {
  return (
    <ol className={styles.rows}>
      {rows.map((row, index) => (
        <li key={row.title}>
          <span className={styles.rowNumber} aria-hidden="true">
            {String(index + 1).padStart(2, '0')}
          </span>
          <div>
            <h3>{row.title}</h3>
            <p>{row.body}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}

function TrendIllustration() {
  return (
    <figure
      className={styles.trend}
      aria-label="Illustrative weight timeline: an example change from 175.2 to 173.4 pounds over 30 days"
    >
      <figcaption className={styles.chapter}>Illustrative timeline / 30 days</figcaption>
      <p className={styles.weight}>
        173.4 <span>lb</span>
      </p>
      <p className={styles.secondary}>Down 1.8 lb over the last 30 days</p>
      <div className={styles.bars} aria-hidden="true">
        {trend.map((height, index) => (
          <span key={index} style={{ height: `${height / 1.7}%` }} />
        ))}
      </div>
      <div className={styles.chartDates} aria-hidden="true">
        <span>30 days ago</span>
        <span>Today</span>
      </div>
      <dl className={styles.sources}>
        <div>
          <dt>Weight</dt>
          <dd>Apple Health · measured</dd>
        </div>
        <div>
          <dt>Body fat</dt>
          <dd>Manual entry · estimated</dd>
        </div>
      </dl>
    </figure>
  );
}

export function EditorialLanding({ appStoreLive }: { appStoreLive: boolean }) {
  return (
    <div className={`${foundation.page} ${styles.page} lyb-marketing`}>
      <a href="#main-content" className={styles.skip}>
        Skip to content
      </a>
      <header className={`${styles.container} ${styles.header}`}>
        <Link href="/" className={styles.brand} aria-label="LogYourBody home">
          LogYourBody
        </Link>
        <nav aria-label="Homepage sections" className={styles.nav}>
          <a href="#the-app">The app</a>
          <a href="#your-progress">Your progress</a>
          <a href="#privacy">Privacy</a>
        </nav>
        <PrimaryAction appStoreLive={appStoreLive} />
      </header>
      <main id="main-content" tabIndex={-1}>
        <section className={`${styles.container} ${styles.hero}`} aria-labelledby="landing-heading">
          <div className={styles.heroCopy}>
            <Chapter>For the work you put in</Chapter>
            <h1 id="landing-heading">{launchLandingCopy.headline}</h1>
            <p className={styles.lead}>{launchLandingCopy.subheading}</p>
            <div className={styles.heroActions}>
              <PrimaryAction appStoreLive={appStoreLive} />
              <a href="#the-app" className={styles.textLink}>
                Explore the app <span aria-hidden="true">↘</span>
              </a>
            </div>
            <p className={styles.platform}>Made for iPhone. Connected to Apple Health.</p>
          </div>
          <figure className={styles.productStage}>
            <Image
              src={LANDING_PRODUCT_PROOF.src}
              alt={LANDING_PRODUCT_PROOF.alt}
              width={LANDING_PRODUCT_PROOF.width}
              height={LANDING_PRODUCT_PROOF.height}
              priority
              sizes="(min-width: 1024px) 300px, 236px"
              className={styles.productImage}
            />
            <figcaption className={styles.chapter}>
              A private timeline. A clearer picture.
            </figcaption>
          </figure>
        </section>
        <div className={`${styles.container} ${styles.heroBaseline}`}>
          <Chapter>01 / See the bigger picture</Chapter>
          <p>Your progress. At your pace.</p>
        </div>
        <section id="the-app" className={styles.shell} aria-labelledby="progress-heading">
          <div className={`${styles.container} ${styles.split} ${styles.section}`}>
            <TrendIllustration />
            <div className={styles.story}>
              <Chapter>02 / The long view</Chapter>
              <h2 id="progress-heading">
                One day is a data point.
                <br />
                You are a trend.
              </h2>
              <p className={styles.lead}>
                Some days the scale moves. Some days it doesn’t. Keep weight, body composition, and
                photos together to see what changes over time.
              </p>
              <FeatureRows rows={launchLandingCopy.signals} />
            </div>
          </div>
        </section>
        <section
          id="your-progress"
          className={`${styles.container} ${styles.section} ${styles.photos}`}
          aria-labelledby="photos-heading"
        >
          <div className={styles.photoIntro}>
            <Chapter>03 / More than a number</Chapter>
            <p>A record only you need to see.</p>
          </div>
          <div className={styles.diptych}>
            <Image
              src="/marketing/landing/editorial-training.webp"
              alt="Athlete taking a quiet pause between sets in a sunlit training studio"
              width={1160}
              height={1240}
              sizes="(min-width: 1024px) 637px, (min-width: 640px) 46vw, 100vw"
            />
            <Image
              src="/marketing/landing/editorial-strength.webp"
              alt="Athlete resting on a bench after a strength session"
              width={1274}
              height={1160}
              sizes="(min-width: 1024px) 637px, (min-width: 640px) 46vw, 100vw"
            />
          </div>
          <div className={styles.split}>
            <h2 id="photos-heading">
              Keep the moments
              <br />
              the numbers miss.
            </h2>
            <div className={styles.story}>
              <p className={styles.lead}>
                Changes can be hard to notice day to day. Keep private progress photos alongside
                your measurements, and look back on your own terms.
              </p>
              <Chapter>Private by default. Personal by design.</Chapter>
            </div>
          </div>
        </section>
        <section id="privacy" className={styles.shell} aria-labelledby="privacy-heading">
          <div className={`${styles.container} ${styles.split} ${styles.section}`}>
            <div className={styles.story}>
              <Chapter>04 / Only for you</Chapter>
              <h2 id="privacy-heading" className={styles.privacyHeading}>
                Your body.
                <br />
                Your business.
              </h2>
              <p className={styles.lead}>
                Progress is personal. Keep a record of yours without making it a performance for
                anyone else.
              </p>
            </div>
            <FeatureRows
              rows={[
                {
                  title: 'A private timeline',
                  body: 'Measurements and photos, without social comparison.',
                },
                {
                  title: 'Connect on your terms',
                  body: 'Read supported Apple Health data, or enter your weight yourself.',
                },
                {
                  title: 'Clear about what it knows',
                  body: 'Measured and estimated values keep their labels and sources.',
                },
              ]}
            />
          </div>
        </section>
        <section
          className={`${styles.container} ${styles.split} ${styles.section}`}
          aria-labelledby="pricing-heading"
        >
          <div className={styles.story}>
            <Chapter>05 / LogYourBody {launchLandingCopy.pricingHeading}</Chapter>
            <h2 id="pricing-heading">
              Make room
              <br />
              for the long game.
            </h2>
            <p className={styles.lead}>
              A private place to keep your progress, and a reason to keep showing up for yourself.
            </p>
          </div>
          <div className={styles.story}>
            <p
              className={styles.price}
              aria-label={`Reference price: ${launchLandingCopy.monthlyReferencePrice} USD per month`}
            >
              {launchLandingCopy.monthlyReferencePrice} <span>USD / month</span>
            </p>
            <p className={styles.annualPrice}>
              Or {launchLandingCopy.annualReferencePrice} USD per year.
            </p>
            <p className={styles.terms}>{launchLandingCopy.pricingNote}</p>
            <PrimaryAction appStoreLive={appStoreLive} />
          </div>
        </section>
        <section id="early-access" className={styles.shell} aria-labelledby="access-heading">
          <div className={`${styles.container} ${styles.section} ${styles.closing}`}>
            <Chapter>Your next chapter</Chapter>
            <h2 id="access-heading">
              Keep showing up.
              <br />
              See what changes.
            </h2>
            <div className={styles.split}>
              <p className={styles.lead}>
                Build a clearer picture of your body, one check-in at a time.{' '}
                {appStoreLive
                  ? 'Get LogYourBody for iPhone.'
                  : 'Join the list for early access to LogYourBody on iPhone.'}
              </p>
              {appStoreLive ? (
                <PrimaryAction appStoreLive />
              ) : (
                <div className={styles.form}>
                  <WaitlistForm landingId="editorial_landing_v1" variant="waitlist_editorial_v2" />
                  <p className={styles.terms}>
                    We’ll email you when access opens.{' '}
                    <Link href="/privacy">Read our Privacy Policy.</Link>
                  </p>
                </div>
              )}
            </div>
          </div>
        </section>
      </main>
      <footer className={`${styles.container} ${styles.footer}`}>
        <Link href="/" className={styles.footerBrand} aria-label="LogYourBody home">
          LogYourBody
        </Link>
        <div className={styles.footerBottom}>
          <p>© {new Date().getFullYear()} LogYourBody, Inc.</p>
          <nav aria-label="Footer">
            <Link href="/support">Support</Link>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/health-disclosure">Health disclosure</Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}
