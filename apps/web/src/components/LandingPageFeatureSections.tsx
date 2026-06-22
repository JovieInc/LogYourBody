import Link from 'next/link';
import {
  BarChart3,
  Camera,
  Check,
  Clock,
  Smartphone,
  TrendingUp,
  type LucideIcon,
} from 'lucide-react';
import { Button } from './ui/button';
import { Badge } from './ui/badge';
import { LandingTimelineDemo } from './LandingTimelineDemo';
import { StepTrackerSection } from './StepTrackerModule';
import { LandingPredictionSection } from './LandingPredictionSection';

type LandingAppFeature = {
  icon: LucideIcon;
  title: string;
  description: string;
};

type LandingPageFeatureSectionsProps = {
  appFeatures: LandingAppFeature[];
};

export function LandingPageFeatureSections({ appFeatures }: LandingPageFeatureSectionsProps) {
  return (
    <>
      {/* Unified Data Import Section - Apple/YC Style */}
      <section className="via-linear-purple/5 bg-gradient-to-b from-transparent to-transparent py-20 md:py-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-5xl">
            {/* Header - Apple style copy */}
            <div className="mb-16 text-center">
              <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                All your body data.
                <br />
                <span className="text-linear-text-secondary">One beautiful timeline.</span>
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-3xl text-lg sm:text-xl">
                Import DEXA scans, progress photos, smart scale measurements, and body measurements.
                We turn your scattered PDFs and spreadsheets into actionable insights.
              </p>
            </div>

            {/* Visual representation - Linear.app inspired */}
            <div className="relative mx-auto max-w-4xl">
              <div className="from-linear-purple/10 to-linear-purple/10 absolute inset-0 bg-gradient-to-r via-transparent blur-3xl" />

              {/* Central hub visualization */}
              <div className="relative grid grid-cols-1 items-center gap-8 md:grid-cols-3">
                {/* Left side - Data sources */}
                <div className="space-y-4">
                  <div className="text-right">
                    <div className="text-linear-text-secondary inline-flex items-center gap-3 text-sm">
                      <span>DEXA Scan PDFs</span>
                      <div className="bg-linear-card border-linear-border/50 flex h-8 w-8 items-center justify-center rounded-lg border">
                        <div className="bg-linear-purple h-1.5 w-1.5 animate-pulse rounded-full" />
                      </div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-linear-text-secondary inline-flex items-center gap-3 text-sm">
                      <span>Smart Scale Data</span>
                      <div className="bg-linear-card border-linear-border/50 flex h-8 w-8 items-center justify-center rounded-lg border">
                        <div className="bg-linear-purple h-1.5 w-1.5 animate-pulse rounded-full" />
                      </div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-linear-text-secondary inline-flex items-center gap-3 text-sm">
                      <span>Progress Photos</span>
                      <div className="bg-linear-card border-linear-border/50 flex h-8 w-8 items-center justify-center rounded-lg border">
                        <div className="bg-linear-purple h-1.5 w-1.5 animate-pulse rounded-full" />
                      </div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-linear-text-secondary inline-flex items-center gap-3 text-sm">
                      <span>Body Measurements</span>
                      <div className="bg-linear-card border-linear-border/50 flex h-8 w-8 items-center justify-center rounded-lg border">
                        <div className="bg-linear-purple h-1.5 w-1.5 animate-pulse rounded-full" />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Center - LogYourBody hub */}
                <div className="relative">
                  <div className="from-linear-purple to-linear-purple/80 mx-auto flex h-32 w-32 items-center justify-center rounded-3xl bg-gradient-to-br shadow-2xl">
                    <BarChart3 className="h-16 w-16 text-white" />
                  </div>
                  <p className="text-linear-text mt-4 text-center font-semibold">LogYourBody</p>
                </div>

                {/* Right side - Unified output */}
                <div className="space-y-4">
                  <div className="text-left">
                    <div className="text-linear-text inline-flex items-center gap-3 text-sm">
                      <div className="bg-linear-purple/10 flex h-8 w-8 items-center justify-center rounded-lg">
                        <Check className="h-4 w-4 text-white" />
                      </div>
                      <span>Unified Timeline</span>
                    </div>
                  </div>
                  <div className="text-left">
                    <div className="text-linear-text inline-flex items-center gap-3 text-sm">
                      <div className="bg-linear-purple/10 flex h-8 w-8 items-center justify-center rounded-lg">
                        <Check className="h-4 w-4 text-white" />
                      </div>
                      <span>Trend Analysis</span>
                    </div>
                  </div>
                  <div className="text-left">
                    <div className="text-linear-text inline-flex items-center gap-3 text-sm">
                      <div className="bg-linear-purple/10 flex h-8 w-8 items-center justify-center rounded-lg">
                        <Check className="h-4 w-4 text-white" />
                      </div>
                      <span>Progress Insights</span>
                    </div>
                  </div>
                  <div className="text-left">
                    <div className="text-linear-text inline-flex items-center gap-3 text-sm">
                      <div className="bg-linear-purple/10 flex h-8 w-8 items-center justify-center rounded-lg">
                        <Check className="h-4 w-4 text-white" />
                      </div>
                      <span>Export Reports</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Connection lines */}
              <div className="pointer-events-none absolute inset-0">
                <svg className="absolute inset-0 h-full w-full" style={{ transform: 'scale(1.1)' }}>
                  <defs>
                    <linearGradient id="gradient-line" x1="0%" y1="0%" x2="100%" y2="0%">
                      <stop offset="0%" stopColor="transparent" />
                      <stop offset="50%" stopColor="rgb(94 106 210 / 0.3)" />
                      <stop offset="100%" stopColor="transparent" />
                    </linearGradient>
                  </defs>
                  {/* Animated connection lines would go here */}
                </svg>
              </div>
            </div>

            {/* Bottom CTA - YC style */}
            <div className="mt-16 text-center">
              <p className="text-linear-text-secondary mb-4 text-sm">
                Stop juggling spreadsheets and PDFs. Start seeing the complete picture.
              </p>
              <Link href="/download/ios">
                <Button className="bg-linear-purple hover:bg-linear-purple/90 rounded-lg px-6 py-2.5 text-sm font-medium text-white transition-all">
                  Import Your Data
                </Button>
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="from-linear-card/20 via-linear-card/10 to-linear-card/20 border-linear-border/50 border-y bg-gradient-to-r py-16">
        <div className="container mx-auto px-4 sm:px-6">
          {/* Companies/Users trust badge */}
          <div className="mb-12 text-center">
            <p className="text-linear-text-tertiary mb-6 text-sm">
              Trusted by fitness professionals worldwide
            </p>
            <div className="flex items-center justify-center gap-8 opacity-60">
              <div className="text-linear-text-secondary text-lg font-semibold">10K+ Users</div>
              <div className="bg-linear-text-tertiary h-1 w-1 rounded-full"></div>
              <div className="text-linear-text-secondary text-lg font-semibold">2M+ Logs</div>
              <div className="bg-linear-text-tertiary h-1 w-1 rounded-full"></div>
              <div className="text-linear-text-secondary text-lg font-semibold">4.9★ Rating</div>
            </div>
          </div>

          {/* Key metrics with better visual hierarchy */}
          <div className="grid grid-cols-2 gap-8 text-center md:grid-cols-4">
            <div className="group">
              <div className="from-linear-text via-linear-text to-linear-text-secondary mb-2 bg-gradient-to-br bg-clip-text text-4xl font-bold text-transparent md:text-5xl">
                10,000+
              </div>
              <div className="text-linear-text-secondary text-sm">Active users</div>
            </div>
            <div className="group">
              <div className="from-linear-text via-linear-text to-linear-text-secondary mb-2 bg-gradient-to-br bg-clip-text text-4xl font-bold text-transparent md:text-5xl">
                2M+
              </div>
              <div className="text-linear-text-secondary text-sm">Measurements logged</div>
            </div>
            <div className="group">
              <div className="from-linear-text via-linear-text to-linear-text-secondary mb-2 bg-gradient-to-br bg-clip-text text-4xl font-bold text-transparent md:text-5xl">
                4.9/5
              </div>
              <div className="text-linear-text-secondary text-sm">App Store rating</div>
            </div>
            <div className="group">
              <div className="from-linear-text via-linear-text to-linear-text-secondary mb-2 bg-gradient-to-br bg-clip-text text-4xl font-bold text-transparent md:text-5xl">
                30 sec
              </div>
              <div className="text-linear-text-secondary text-sm">Average log time</div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Grid */}
      <section id="features-grid" className="py-24 md:py-32" aria-labelledby="features-heading">
        <div className="container mx-auto px-4 sm:px-6">
          {/* Section header */}
          <div className="mb-20 text-center">
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-6 text-white">
              Core Features
            </Badge>
            <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
              Everything you need to
              <br />
              <span className="from-linear-text via-linear-purple to-linear-text bg-gradient-to-r bg-clip-text text-transparent">
                track real progress
              </span>
            </h2>
            <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
              Professional-grade body composition tracking with the simplicity of a modern app.
            </p>
          </div>

          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4" role="list">
            <div
              id="advanced-analytics"
              className="border-linear-border/50 from-linear-card/50 hover:border-linear-purple/30 hover:bg-linear-card/30 group relative rounded-2xl border bg-gradient-to-br to-transparent p-8 transition-all duration-300"
              role="listitem"
            >
              <div className="mb-6">
                <div className="bg-linear-purple/10 group-hover:bg-linear-purple/20 inline-flex h-12 w-12 items-center justify-center rounded-xl transition-colors">
                  <BarChart3 className="h-6 w-6 text-white" aria-hidden="true" />
                </div>
              </div>
              <h3 className="text-linear-text mb-3 text-lg font-semibold">Advanced Analytics</h3>
              <p className="text-linear-text-secondary text-sm leading-relaxed">
                See what&apos;s really changing. Track body fat percentage, FFMI, and lean mass with
                scientific precision.
              </p>
            </div>

            <div
              id="progress-photos-grid"
              className="border-linear-border/50 from-linear-card/50 hover:border-linear-purple/30 hover:bg-linear-card/30 group relative rounded-2xl border bg-gradient-to-br to-transparent p-8 transition-all duration-300"
              role="listitem"
            >
              <div className="mb-6">
                <div className="bg-linear-purple/10 group-hover:bg-linear-purple/20 inline-flex h-12 w-12 items-center justify-center rounded-xl transition-colors">
                  <Camera className="h-6 w-6 text-white" aria-hidden="true" />
                </div>
              </div>
              <h3 className="text-linear-text mb-3 text-lg font-semibold">Progress Photos</h3>
              <p className="text-linear-text-secondary text-sm leading-relaxed">
                Automated photo reminders with consistent angles. Side-by-side comparisons that show
                real progress.
              </p>
            </div>

            <div
              id="health-app-sync"
              className="border-linear-border/50 from-linear-card/50 hover:border-linear-purple/30 hover:bg-linear-card/30 group relative rounded-2xl border bg-gradient-to-br to-transparent p-8 transition-all duration-300"
              role="listitem"
            >
              <div className="mb-6">
                <div className="bg-linear-purple/10 group-hover:bg-linear-purple/20 inline-flex h-12 w-12 items-center justify-center rounded-xl transition-colors">
                  <Smartphone className="h-6 w-6 text-white" aria-hidden="true" />
                </div>
              </div>
              <h3 className="text-linear-text mb-3 text-lg font-semibold">Health App Sync</h3>
              <p className="text-linear-text-secondary text-sm leading-relaxed">
                Auto-imports from Apple Health and Google Fit. Zero manual entry, always up to date.
              </p>
            </div>

            <div
              id="progress-insights"
              className="border-linear-border/50 from-linear-card/50 hover:border-linear-purple/30 hover:bg-linear-card/30 group relative rounded-2xl border bg-gradient-to-br to-transparent p-8 transition-all duration-300"
              role="listitem"
            >
              <div className="mb-6">
                <div className="bg-linear-purple/10 group-hover:bg-linear-purple/20 inline-flex h-12 w-12 items-center justify-center rounded-xl transition-colors">
                  <TrendingUp className="h-6 w-6 text-white" aria-hidden="true" />
                </div>
              </div>
              <h3 className="text-linear-text mb-3 text-lg font-semibold">Progress Insights</h3>
              <p className="text-linear-text-secondary text-sm leading-relaxed">
                Intelligent trend analysis and predictions. Spot patterns before they become
                problems.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Main Features Section */}
      <section id="main-features" className="py-20 md:py-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mb-4 text-center">
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-4 inline-block text-white">
              Used by 10,000+ users
            </Badge>
          </div>
          <h2 className="text-linear-text mb-8 text-center text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl lg:text-6xl">
            Finally see if your
            <br />
            workout plan works
          </h2>
          <p className="text-linear-text-secondary mx-auto mb-12 max-w-2xl text-center text-base sm:text-lg">
            Stop guessing. Start measuring. Track the metrics that actually matter for body
            composition.
          </p>

          {/* Feature cards */}
          <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
            {appFeatures.map((feature, index) => (
              <div
                key={index}
                className="border-linear-border bg-linear-card hover:border-linear-text-tertiary group rounded-lg border p-6 transition-colors"
              >
                <feature.icon className="mb-4 h-8 w-8 text-white" />
                <h3 className="text-linear-text mb-2 text-lg font-semibold">{feature.title}</h3>
                <p className="text-linear-text-secondary text-sm leading-relaxed">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Timeline Feature Section */}
      <section id="timeline-feature" className="relative overflow-hidden py-20 md:py-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="grid gap-16 lg:grid-cols-2 lg:items-center">
            {/* Content */}
            <div className="order-2 lg:order-1">
              <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-4 inline-block text-white">
                Game-changing feature
              </Badge>
              <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl lg:text-6xl">
                Your body&apos;s time machine
              </h2>
              <p className="text-linear-text-secondary mb-8 text-lg sm:text-xl">
                Slide through time. See exactly how you looked on any date. Body fat, weight, FFMI —
                with photos to prove it.
              </p>

              <div className="space-y-6">
                <div className="flex gap-4">
                  <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                    <Clock className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <h3 className="text-linear-text mb-1 text-lg font-semibold">
                      Instant time travel
                    </h3>
                    <p className="text-linear-text-secondary">
                      Drag the slider. Jump to any date. See your exact stats and photo from that
                      day.
                    </p>
                  </div>
                </div>

                <div className="flex gap-4">
                  <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                    <Camera className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <h3 className="text-linear-text mb-1 text-lg font-semibold">Visual proof</h3>
                    <p className="text-linear-text-secondary">
                      Every data point paired with your progress photo. No more guessing if
                      you&apos;ve changed.
                    </p>
                  </div>
                </div>

                <div className="flex gap-4">
                  <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                    <TrendingUp className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <h3 className="text-linear-text mb-1 text-lg font-semibold">
                      Spot patterns instantly
                    </h3>
                    <p className="text-linear-text-secondary">
                      See when you peaked. When you plateaued. What actually worked.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {/* Visual Demo */}
            <div className="order-1 lg:order-2">
              <div className="relative">
                {/* Background gradient */}
                <div className="from-linear-purple/20 absolute inset-0 bg-gradient-to-br via-transparent to-transparent blur-3xl" />

                {/* Interactive timeline demo */}
                <LandingTimelineDemo />
              </div>
            </div>
          </div>
        </div>
      </section>

      <StepTrackerSection />

      <LandingPredictionSection />
    </>
  );
}
