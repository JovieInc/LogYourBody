'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import {
  Activity,
  Apple,
  ArrowRight,
  Camera,
  Check,
  ChevronRight,
  Dumbbell,
  HeartPulse,
  LockKeyhole,
  Ruler,
  Shield,
  Sparkles,
  TrendingDown,
  TrendingUp,
  Watch,
} from 'lucide-react';
import { Footer } from '@/components/Footer';
import { Header } from '@/components/Header';
import { APP_CONFIG } from '@/constants/app';
import { analytics } from '@/lib/analytics';
import { cn } from '@/lib/utils';
import { getPricingPlanNote, landingSectionHeadings } from './home-page-copy';

const proofStats = [
  { value: '30 sec', label: 'average log time' },
  { value: '3', label: 'body fat methods' },
  { value: '4.9/5', label: 'App Store rating' },
  { value: APP_CONFIG.trialLengthText, label: 'before billing' },
];

const hudMetrics = [
  { label: 'Body fat', value: '14.8%', delta: '-3.2%', tone: 'text-sky-300' },
  { label: 'Lean mass', value: '162 lb', delta: '+4.8 lb', tone: 'text-emerald-300' },
  { label: 'FFMI', value: '22.9', delta: '+0.6', tone: 'text-amber-200' },
];

const featureTiles = [
  {
    id: 'track-metrics',
    icon: Ruler,
    title: 'Body composition, not vanity weight',
    body: 'Log weight, body fat, lean mass, FFMI, waist, photos, and notes in one tight daily flow.',
  },
  {
    id: 'health-sync',
    icon: Watch,
    title: 'HealthKit keeps the baseline current',
    body: 'Weight and step data can arrive from Apple Health, so manual input stays reserved for what matters.',
  },
  {
    id: 'analyze-progress',
    icon: TrendingUp,
    title: 'Phase-aware insight',
    body: 'Short deterministic feedback classifies cutting, maintaining, or gaining from trend data.',
  },
  {
    id: 'privacy',
    icon: LockKeyhole,
    title: 'Private by default',
    body: 'Progress photos and health data are treated like personal records, not social content.',
  },
];

const progressPhotos = [
  { src: '/avatars-v2/m_bf25.png', label: 'Week 1', metric: '23% BF' },
  { src: '/avatars-v2/m_bf20.png', label: 'Week 6', metric: '19% BF' },
  { src: '/avatars-v2/m_bf15.png', label: 'Week 14', metric: '15% BF' },
];

const timeline = [
  {
    label: 'Jan',
    phase: 'Cut starts',
    bodyFat: '21.4%',
    weight: '187 lb',
    leanMass: '147 lb',
    note: 'Weight drops, lean mass holds steady.',
  },
  {
    label: 'Feb',
    phase: 'Momentum',
    bodyFat: '18.9%',
    weight: '181 lb',
    leanMass: '147 lb',
    note: 'Photos confirm waist change before scale slows.',
  },
  {
    label: 'Mar',
    phase: 'Plateau warning',
    bodyFat: '17.8%',
    weight: '179 lb',
    leanMass: '147 lb',
    note: 'The app flags a stalled trend before motivation drops.',
  },
  {
    label: 'Apr',
    phase: 'Maintenance',
    bodyFat: '15.6%',
    weight: '176 lb',
    leanMass: '149 lb',
    note: 'Phase shifts from cutting to maintainable progress.',
  },
];

const socialStats = [
  { value: '10k+', label: 'people tracking' },
  { value: '500k+', label: 'measurements logged' },
  { value: '93%', label: 'goal follow-through' },
  { value: '0', label: 'ads or feeds' },
];

const deepDives = [
  {
    id: 'progress-photos',
    icon: Camera,
    title: 'Zero-click progress photos',
    body: 'Consistent reminders, aligned comparisons, and optional cleanup make visual progress usable without turning it into a photo project.',
    detail: 'Aligned front, side, and back views',
  },
  {
    id: 'timeline-view',
    icon: Activity,
    title: 'Your body over time',
    body: 'Every meaningful input lands on one timeline, so scale, body fat, lean mass, steps, and photos tell the same story.',
    detail: 'Photos, metrics, and phases together',
  },
  {
    id: 'step-tracking',
    icon: Dumbbell,
    title: 'Activity context',
    body: 'Steps explain recovery and energy balance without asking users to become full-time workout loggers.',
    detail: 'Movement context without workout tracking',
  },
];

const planFeatures = [
  'Body fat, FFMI, lean mass, and weight trends',
  'Progress photo reminders and comparisons',
  'Apple Health weight and step sync',
  'Private export whenever you want it',
  'Short weekly progress summaries',
];

export function FullLandingPage() {
  const [isAnnual, setIsAnnual] = useState(true);
  const [timelineIndex, setTimelineIndex] = useState(timeline.length - 1);
  const currentPlan = isAnnual ? APP_CONFIG.pricing.annual : APP_CONFIG.pricing.monthly;
  const selectedEntry = timeline[timelineIndex];

  useEffect(() => {
    analytics.track('web_landing_viewed');
  }, []);

  const scrollToSection = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const handleCtaClick = (id: string) => {
    analytics.track('web_cta_clicked', { id });
  };

  return (
    <div className="font-inter min-h-screen bg-[#050506] text-white">
      <Header onFeatureClick={scrollToSection} showFeatures />

      <main id="main-content" tabIndex={-1}>
        <section
          data-testid="landing-hero"
          className="relative isolate overflow-hidden border-b border-white/10"
          aria-labelledby="hero-heading"
        >
          <div className="absolute inset-0 -z-10 bg-[linear-gradient(180deg,#090a0c_0%,#050506_74%)]" />
          <div className="absolute inset-y-0 right-0 -z-10 hidden w-[58%] border-l border-white/10 bg-[#0b0d10] lg:block">
            <div className="h-full bg-[linear-gradient(90deg,rgba(5,5,6,0.94)_0%,rgba(5,5,6,0.42)_42%,rgba(5,5,6,0)_100%)]" />
          </div>

          <div className="mx-auto grid max-w-7xl gap-10 px-6 pb-14 pt-20 sm:pb-16 sm:pt-24 lg:grid-cols-[0.92fr_1.08fr] lg:items-center lg:px-8 lg:pb-20 lg:pt-28">
            <div className="max-w-2xl">
              <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1 text-sm text-white/70">
                <Sparkles className="h-4 w-4 text-sky-300" />
                Built for photo-first body composition tracking
              </div>

              <h1
                id="hero-heading"
                className="text-5xl font-semibold leading-none text-white sm:text-6xl lg:text-7xl"
              >
                {landingSectionHeadings.hero}
              </h1>
              <p className="text-white/68 mt-6 max-w-xl text-lg leading-8 sm:text-xl">
                A private iPhone body-composition heads-up display for people who already train,
                weigh in, and want to know how they are actually doing.
              </p>

              <div className="mt-8 flex flex-col gap-3 sm:flex-row">
                <Link
                  href="/download/ios"
                  onClick={() => handleCtaClick('hero_download_ios')}
                  className="hover:bg-white/88 inline-flex min-h-12 items-center justify-center rounded-full bg-white px-6 text-sm font-semibold text-black transition focus:outline-none focus:ring-2 focus:ring-white/40"
                >
                  <Apple className="mr-2 h-4 w-4" />
                  Download for iOS
                </Link>
                <button
                  type="button"
                  onClick={() => {
                    handleCtaClick('hero_view_timeline');
                    scrollToSection('timeline-view');
                  }}
                  className="border-white/14 text-white/86 hover:border-white/24 inline-flex min-h-12 items-center justify-center rounded-full border px-6 text-sm font-semibold transition hover:bg-white/[0.05] focus:outline-none focus:ring-2 focus:ring-sky-300/35"
                >
                  View the timeline
                  <ChevronRight className="ml-1 h-4 w-4" />
                </button>
              </div>

              <div className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
                {proofStats.map((stat) => (
                  <div key={stat.label} className="border-t border-white/10 pt-3">
                    <div className="text-base font-semibold text-white">{stat.value}</div>
                    <div className="mt-1 text-xs leading-5 text-white/50">{stat.label}</div>
                  </div>
                ))}
              </div>
            </div>

            <HeroPhone />
          </div>
        </section>

        <section
          data-testid="stats-band"
          className="border-b border-white/10 bg-[#08090b] py-8"
          aria-label="LogYourBody proof points"
        >
          <div className="mx-auto grid max-w-7xl grid-cols-2 gap-4 px-6 sm:grid-cols-4 lg:px-8">
            {socialStats.map((stat) => (
              <div
                key={stat.label}
                className="rounded-lg border border-white/10 bg-white/[0.03] px-4 py-5"
              >
                <div className="text-3xl font-semibold text-white">{stat.value}</div>
                <div className="text-white/54 mt-2 text-sm">{stat.label}</div>
              </div>
            ))}
          </div>
        </section>

        <section
          id="progress-photos"
          data-testid="progress-photos"
          className="bg-[#050506] py-16 sm:py-20"
        >
          <div className="mx-auto max-w-7xl px-6 lg:px-8">
            <div className="grid gap-10 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
              <div>
                <div className="mb-4 inline-flex items-center rounded-full border border-sky-300/20 bg-sky-300/10 px-3 py-1 text-sm font-medium text-sky-200">
                  Zero-click progress photos
                </div>
                <h2 className="text-4xl font-semibold leading-tight text-white sm:text-5xl">
                  {landingSectionHeadings.photos}
                </h2>
                <p className="text-white/64 mt-5 max-w-xl text-lg leading-8">
                  Progress photos sit beside body fat, FFMI, lean mass, and weight, so users can see
                  whether the cut, gain, or maintenance phase is really working.
                </p>
              </div>

              <div className="grid grid-cols-3 gap-3 sm:gap-4">
                {progressPhotos.map((photo) => (
                  <figure
                    key={photo.src}
                    className="overflow-hidden rounded-lg border border-white/10 bg-white/[0.04]"
                  >
                    <div className="relative aspect-[4/5] bg-[#111316]">
                      <Image
                        src={photo.src}
                        alt={`${photo.label} body-composition avatar at ${photo.metric}`}
                        fill
                        sizes="(min-width: 1024px) 16vw, 30vw"
                        className="object-contain p-3"
                      />
                    </div>
                    <figcaption className="border-t border-white/10 px-3 py-3">
                      <div className="text-sm font-semibold text-white">{photo.label}</div>
                      <div className="text-white/52 mt-1 text-xs">{photo.metric}</div>
                    </figcaption>
                  </figure>
                ))}
              </div>
            </div>
          </div>
        </section>

        <section
          id="features"
          data-testid="feature-deep-dives"
          className="border-y border-white/10 bg-[#0a0b0d] py-16 sm:py-20"
        >
          <div className="mx-auto max-w-7xl px-6 lg:px-8">
            <div className="max-w-2xl">
              <h2 className="text-4xl font-semibold leading-tight text-white sm:text-5xl">
                {landingSectionHeadings.features}
              </h2>
              <p className="text-white/62 mt-5 text-lg leading-8">
                LogYourBody stays a body-composition cockpit. No food diary. No workout feed. Just
                the signals that answer how you are doing.
              </p>
            </div>

            <div className="mt-10 grid gap-4 md:grid-cols-2">
              {featureTiles.map((feature) => (
                <article
                  key={feature.id}
                  id={feature.id}
                  className="rounded-lg border border-white/10 bg-white/[0.035] p-6"
                >
                  <div className="mb-5 flex h-11 w-11 items-center justify-center rounded-lg bg-white/[0.06]">
                    <feature.icon className="h-5 w-5 text-sky-200" />
                  </div>
                  <h3 className="text-xl font-semibold text-white">{feature.title}</h3>
                  <p className="text-white/58 mt-3 leading-7">{feature.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section
          id="timeline-view"
          data-testid="timeline-section"
          className="bg-[#050506] py-16 sm:py-20"
        >
          <div className="mx-auto max-w-7xl px-6 lg:px-8">
            <div className="grid gap-10 lg:grid-cols-[0.88fr_1.12fr] lg:items-center">
              <div>
                <div className="mb-4 inline-flex items-center rounded-full border border-emerald-300/20 bg-emerald-300/10 px-3 py-1 text-sm font-medium text-emerald-200">
                  Signature timeline
                </div>
                <h2 className="text-4xl font-semibold leading-tight text-white sm:text-5xl">
                  {landingSectionHeadings.timeline}
                </h2>
                <p className="text-white/62 mt-5 text-lg leading-8">
                  The timeline keeps phases, photos, and body-composition metrics in one place, so a
                  plateau is a visible state instead of a vague feeling.
                </p>
              </div>

              <div className="rounded-lg border border-white/10 bg-[#0d0f12] p-5 sm:p-6">
                <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="text-sm text-white/50">{selectedEntry.label}</div>
                    <div className="mt-1 text-2xl font-semibold text-white">
                      {selectedEntry.phase}
                    </div>
                  </div>
                  <div className="text-white/64 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1 text-sm">
                    {selectedEntry.note}
                  </div>
                </div>

                <div className="grid gap-3 sm:grid-cols-3">
                  <MetricTile
                    label="Body fat"
                    value={selectedEntry.bodyFat}
                    icon={TrendingDown}
                    tone="text-sky-300"
                  />
                  <MetricTile
                    label="Weight"
                    value={selectedEntry.weight}
                    icon={Activity}
                    tone="text-white"
                  />
                  <MetricTile
                    label="Lean mass"
                    value={selectedEntry.leanMass}
                    icon={TrendingUp}
                    tone="text-emerald-300"
                  />
                </div>

                <label className="mt-8 block">
                  <span className="sr-only">Timeline month</span>
                  <input
                    type="range"
                    min={0}
                    max={timeline.length - 1}
                    step={1}
                    value={timelineIndex}
                    onChange={(event) => setTimelineIndex(Number(event.target.value))}
                    className="bg-white/12 h-2 w-full cursor-pointer appearance-none rounded-full accent-sky-300"
                  />
                </label>

                <div className="mt-4 grid grid-cols-4 gap-2">
                  {timeline.map((item, index) => (
                    <button
                      key={item.label}
                      type="button"
                      onClick={() => setTimelineIndex(index)}
                      className={cn(
                        'min-h-11 rounded-lg border px-3 text-sm transition',
                        timelineIndex === index
                          ? 'bg-sky-300/12 border-sky-300/40 text-white'
                          : 'text-white/56 border-white/10 bg-white/[0.03] hover:bg-white/[0.06]',
                      )}
                    >
                      {item.label}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          id="step-tracking"
          className="border-y border-white/10 bg-[#08090b] py-16 sm:py-20"
        >
          <div className="mx-auto max-w-7xl px-6 lg:px-8">
            <div className="grid gap-4 lg:grid-cols-3">
              {deepDives.map((item) => (
                <article
                  key={item.id}
                  className="rounded-lg border border-white/10 bg-white/[0.035] p-6"
                >
                  <item.icon className="h-6 w-6 text-sky-200" />
                  <h3 className="mt-5 text-2xl font-semibold text-white">{item.title}</h3>
                  <p className="mt-4 leading-7 text-white/60">{item.body}</p>
                  <div className="text-white/48 mt-6 border-t border-white/10 pt-4 text-sm">
                    {item.detail}
                  </div>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="pricing" data-testid="pricing-section" className="bg-[#050506] py-16 sm:py-20">
          <div className="mx-auto max-w-7xl px-6 lg:px-8">
            <div className="grid gap-10 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
              <div>
                <h2 className="text-4xl font-semibold leading-tight text-white sm:text-5xl">
                  {landingSectionHeadings.pricing}
                </h2>
                <p className="text-white/62 mt-5 text-lg leading-8">
                  The paid iOS app is the product surface. Web stays focused on marketing, legal,
                  support, billing, and account paths until usage proves otherwise.
                </p>

                <div className="mt-8 inline-flex rounded-full border border-white/10 bg-white/[0.04] p-1">
                  <button
                    type="button"
                    onClick={() => setIsAnnual(false)}
                    className={cn(
                      'min-h-10 rounded-full px-4 text-sm font-semibold transition',
                      !isAnnual ? 'bg-white text-black' : 'text-white/58 hover:text-white',
                    )}
                  >
                    Monthly
                  </button>
                  <button
                    type="button"
                    onClick={() => setIsAnnual(true)}
                    className={cn(
                      'min-h-10 rounded-full px-4 text-sm font-semibold transition',
                      isAnnual ? 'bg-white text-black' : 'text-white/58 hover:text-white',
                    )}
                  >
                    Annual
                  </button>
                </div>
              </div>

              <div className="rounded-lg border border-white/10 bg-[#0d0f12] p-6">
                <div className="flex flex-wrap items-start justify-between gap-4 border-b border-white/10 pb-6">
                  <div>
                    <div className="text-white/46 text-sm font-medium uppercase">
                      LogYourBody Pro
                    </div>
                    <div className="mt-3 flex items-end gap-2">
                      <span className="text-5xl font-semibold text-white">
                        ${currentPlan.price}
                      </span>
                      <span className="text-white/52 pb-2">/{currentPlan.period}</span>
                    </div>
                    {isAnnual ? (
                      <p className="mt-3 text-sm text-emerald-300">{getPricingPlanNote(true)}</p>
                    ) : (
                      <p className="text-white/52 mt-3 text-sm">{getPricingPlanNote(false)}</p>
                    )}
                  </div>
                  <div className="rounded-full border border-emerald-300/20 bg-emerald-300/10 px-3 py-1 text-sm text-emerald-200">
                    {APP_CONFIG.trialLengthText}
                  </div>
                </div>

                <ul className="mt-6 space-y-4">
                  {planFeatures.map((feature) => (
                    <li key={feature} className="flex gap-3 text-white/70">
                      <Check className="mt-0.5 h-5 w-5 flex-none text-emerald-300" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>

                <Link
                  href="/download/ios"
                  onClick={() => handleCtaClick('pricing_start_trial')}
                  className="hover:bg-white/88 mt-8 inline-flex min-h-12 w-full items-center justify-center rounded-full bg-white px-5 text-sm font-semibold text-black transition focus:outline-none focus:ring-2 focus:ring-white/40"
                >
                  Start free trial
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Link>
              </div>
            </div>
          </div>
        </section>

        <section className="border-y border-white/10 bg-[#0a0b0d] py-16 sm:py-20">
          <div className="mx-auto max-w-4xl px-6 text-center">
            <Shield className="mx-auto h-9 w-9 text-sky-200" />
            <h2 className="mt-6 text-4xl font-semibold leading-tight text-white sm:text-5xl">
              A body-composition HUD, not another feed.
            </h2>
            <p className="text-white/62 mx-auto mt-5 max-w-2xl text-lg leading-8">
              Built around private records, short insight, and less input. The app answers how you
              are doing without asking you to rebuild your whole fitness system.
            </p>
            <Link
              href="/download/ios"
              onClick={() => handleCtaClick('final_download_ios')}
              className="hover:bg-white/88 mt-8 inline-flex min-h-12 items-center justify-center rounded-full bg-white px-6 text-sm font-semibold text-black transition"
            >
              Download LogYourBody
              <ArrowRight className="ml-2 h-4 w-4" />
            </Link>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}

function HeroPhone() {
  return (
    <div
      className="relative mx-auto w-full max-w-[42rem] lg:mx-0"
      aria-label="LogYourBody app preview"
    >
      <div className="bg-white/12 absolute inset-x-6 top-8 h-px" />
      <div className="border-white/14 relative mx-auto w-[min(22rem,calc(100vw-3rem))] rounded-[2rem] border bg-[#121418] p-3 shadow-2xl">
        <div className="overflow-hidden rounded-[1.45rem] border border-white/10 bg-[#050506]">
          <div className="flex items-center justify-between border-b border-white/10 px-4 py-3 text-xs text-white/45">
            <span>Today</span>
            <HeartPulse className="h-4 w-4 text-rose-300" />
          </div>
          <div className="relative aspect-[9/12] bg-[#0c0e11]">
            <Image
              src="/avatars-v2/m_bf15.png"
              alt="LogYourBody body-composition avatar preview"
              fill
              priority
              sizes="(min-width: 1024px) 20rem, 80vw"
              className="object-contain p-5"
            />
          </div>
          <div className="grid grid-cols-3 border-t border-white/10">
            {hudMetrics.map((metric) => (
              <div key={metric.label} className="border-r border-white/10 p-3 last:border-r-0">
                <div className="text-white/42 text-[11px]">{metric.label}</div>
                <div className="mt-1 text-lg font-semibold text-white">{metric.value}</div>
                <div className={cn('mt-1 text-[11px] font-medium', metric.tone)}>
                  {metric.delta}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function MetricTile({
  label,
  value,
  icon: Icon,
  tone,
}: {
  label: string;
  value: string;
  icon: typeof Activity;
  tone: string;
}) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/[0.035] p-4">
      <div className="flex items-center justify-between gap-3">
        <span className="text-white/48 text-sm">{label}</span>
        <Icon className={cn('h-4 w-4', tone)} />
      </div>
      <div className="mt-3 text-3xl font-semibold text-white">{value}</div>
    </div>
  );
}
