import Link from 'next/link';
import { Check, Download, Monitor, Smartphone, Tablet, Zap } from 'lucide-react';
import { Button } from './ui/button';
import { Badge } from './ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from './ui/card';
import { Switch } from './ui/switch';
import { APP_CONFIG } from '@/constants/app';

type PricingConfig = {
  monthly: {
    price: number;
    period: string;
    yearlyTotal: number;
  };
  annual: {
    price: number;
    period: string;
    monthlyEquivalent: number;
    savings: number;
    savingsPercent: number;
  };
};

type LandingPageConversionSectionsProps = {
  features: string[];
  isAnnual: boolean;
  setIsAnnual: (isAnnual: boolean) => void;
  pricing: PricingConfig;
  currentPlan: PricingConfig['monthly'] | PricingConfig['annual'];
};

export function LandingPageConversionSections({
  features,
  isAnnual,
  setIsAnnual,
  pricing,
  currentPlan,
}: LandingPageConversionSectionsProps) {
  return (
    <>
      {/* Cross-Platform Section */}
      <section className="bg-linear-card/30 py-20 md:py-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-6xl">
            <div className="mb-16 text-center">
              <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-6 inline-block text-white">
                Available Everywhere
              </Badge>
              <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                Your data follows you
                <br />
                <span className="from-linear-text via-linear-purple to-linear-text bg-gradient-to-r bg-clip-text text-transparent">
                  everywhere you go
                </span>
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                Whether you&apos;re at home, in the gym, or traveling, LogYourBody works seamlessly
                across all your devices with real-time sync.
              </p>
            </div>

            <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
              {/* Visual Content */}
              <div className="relative">
                {/* Device mockups */}
                <div className="relative">
                  {/* Desktop mockup */}
                  <div className="border-linear-border/50 bg-linear-card/50 rounded-2xl border p-6 shadow-xl backdrop-blur-sm">
                    <div className="mb-4 flex items-center gap-3">
                      <div className="flex gap-2">
                        <div className="h-3 w-3 rounded-full bg-red-500/60"></div>
                        <div className="h-3 w-3 rounded-full bg-yellow-500/60"></div>
                        <div className="h-3 w-3 rounded-full bg-green-500/60"></div>
                      </div>
                      <div className="flex-1 text-center">
                        <div className="bg-linear-border/30 mx-auto h-4 w-48 rounded"></div>
                      </div>
                    </div>
                    <div className="from-linear-purple/10 to-linear-purple/5 border-linear-border/30 flex aspect-[16/10] items-center justify-center rounded-lg border bg-gradient-to-br">
                      <div className="text-center">
                        <Monitor className="mx-auto mb-3 h-12 w-12 text-white/50" />
                        <p className="text-linear-text-secondary text-sm">Web Dashboard</p>
                      </div>
                    </div>
                  </div>

                  {/* Mobile mockup - positioned to overlap */}
                  <div className="border-linear-border/50 bg-linear-card/80 absolute -bottom-8 -right-8 w-48 rounded-2xl border p-4 shadow-xl backdrop-blur-sm">
                    <div className="mb-3 flex justify-center">
                      <div className="bg-linear-border/50 h-1 w-12 rounded-full"></div>
                    </div>
                    <div className="from-linear-purple/10 to-linear-purple/5 border-linear-border/30 flex aspect-[9/16] items-center justify-center rounded-lg border bg-gradient-to-br">
                      <div className="text-center">
                        <Smartphone className="mx-auto mb-2 h-8 w-8 text-white/50" />
                        <p className="text-linear-text-secondary text-xs">Mobile App</p>
                      </div>
                    </div>
                  </div>

                  {/* Sync indicator */}
                  <div className="absolute left-1/2 top-1/2 z-10 -translate-x-1/2 -translate-y-1/2">
                    <div className="bg-linear-bg/90 border-linear-border/50 rounded-full border p-3 shadow-lg backdrop-blur-sm">
                      <Zap className="h-6 w-6 animate-pulse text-white" />
                    </div>
                  </div>
                </div>
              </div>

              {/* Content */}
              <div className="space-y-8">
                <div>
                  <h3 className="text-linear-text mb-4 text-2xl font-bold">
                    One app, every platform
                  </h3>
                  <p className="text-linear-text-secondary mb-6 text-lg">
                    Log your metrics on your phone at the gym, review progress on your laptop at
                    home, or check trends on your tablet anywhere. Your data syncs instantly across
                    all devices.
                  </p>
                </div>

                <div className="grid gap-6 sm:grid-cols-2">
                  <div className="flex gap-4">
                    <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                      <Smartphone className="h-6 w-6 text-white" />
                    </div>
                    <div>
                      <h4 className="text-linear-text mb-1 font-semibold">Native Mobile Apps</h4>
                      <p className="text-linear-text-secondary text-sm">
                        Full-featured iOS and Android apps with offline support and HealthKit
                        integration.
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                      <Monitor className="h-6 w-6 text-white" />
                    </div>
                    <div>
                      <h4 className="text-linear-text mb-1 font-semibold">Web Dashboard</h4>
                      <p className="text-linear-text-secondary text-sm">
                        Powerful web interface perfect for detailed analysis and data management.
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                      <Tablet className="h-6 w-6 text-white" />
                    </div>
                    <div>
                      <h4 className="text-linear-text mb-1 font-semibold">Tablet Optimized</h4>
                      <p className="text-linear-text-secondary text-sm">
                        Perfect for coaching sessions and reviewing progress with larger charts and
                        graphs.
                      </p>
                    </div>
                  </div>

                  <div className="flex gap-4">
                    <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                      <Zap className="h-6 w-6 text-white" />
                    </div>
                    <div>
                      <h4 className="text-linear-text mb-1 font-semibold">Real-time Sync</h4>
                      <p className="text-linear-text-secondary text-sm">
                        Log on one device, see it instantly on all others. No manual syncing
                        required.
                      </p>
                    </div>
                  </div>
                </div>

                <div className="border-linear-border/50 bg-linear-bg/50 rounded-lg border p-6">
                  <div className="mb-3 flex items-center gap-3">
                    <Download className="h-5 w-5 text-white" />
                    <h4 className="text-linear-text font-semibold">Get started today</h4>
                  </div>
                  <p className="text-linear-text-secondary mb-4 text-sm">
                    Download the app or sign up on the web. Your account works everywhere from day
                    one.
                  </p>
                  <div className="flex flex-col gap-3 sm:flex-row">
                    <Link href="/download/ios">
                      <Button className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary transition-colors">
                        Start Free Trial
                      </Button>
                    </Link>
                    <Button
                      variant="outline"
                      className="border-linear-border text-linear-text-secondary hover:bg-linear-border/30 hover:text-linear-text"
                      onClick={() => window.open(APP_CONFIG.appStoreUrl, '_blank')}
                    >
                      <Smartphone className="mr-2 h-4 w-4" />
                      Download App
                    </Button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Pricing Section */}
      <section id="pricing" className="container mx-auto px-4 py-20 sm:px-6">
        <div className="mb-16 text-center">
          <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
            Less than your protein powder
          </h2>
          <p className="text-linear-text-secondary text-lg sm:text-xl">
            3 days free. Then $5.83/month. Cancel anytime.
          </p>
        </div>

        {/* Billing Toggle */}
        <div
          className="not-prose mb-12 flex items-center justify-center gap-4"
          role="group"
          aria-labelledby="billing-toggle-label"
        >
          <span id="billing-toggle-label" className="sr-only">
            Choose billing frequency
          </span>
          <span
            className={`text-lg font-medium ${!isAnnual ? 'text-linear-text' : 'text-linear-text-tertiary'}`}
            id="monthly-label"
          >
            Monthly
          </span>
          <Switch
            checked={isAnnual}
            onCheckedChange={setIsAnnual}
            className="focus:ring-linear-purple/50 data-[state=checked]:bg-linear-purple focus:ring-2"
            aria-labelledby="monthly-label annual-label"
            aria-describedby="billing-savings"
          />
          <span
            className={`text-lg font-medium ${isAnnual ? 'text-linear-text' : 'text-linear-text-tertiary'}`}
            id="annual-label"
          >
            Annual
          </span>
          {isAnnual && (
            <Badge
              id="billing-savings"
              className="ml-2 border-green-200 bg-green-100 text-green-800"
              role="status"
            >
              Save {pricing.annual.savingsPercent}%
            </Badge>
          )}
        </div>

        {/* Single Pricing Card */}
        <div className="not-prose mx-auto max-w-md">
          <Card
            className="border-linear-border bg-linear-card ring-linear-border focus-within:ring-linear-purple/50 relative shadow-xl ring-1 focus-within:ring-2"
            role="region"
            aria-labelledby="pricing-title"
            aria-describedby="pricing-description"
          >
            <Badge
              className="bg-linear-purple absolute -top-3 left-1/2 -translate-x-1/2 transform text-white"
              role="status"
            >
              3-Day Free Trial
            </Badge>
            <CardHeader className="text-center">
              <CardTitle id="pricing-title" className="text-linear-text text-2xl">
                Full Access
              </CardTitle>
              <div className="mt-4">
                <span className="text-linear-text text-4xl font-bold transition-all duration-300 ease-in-out">
                  <span className="sr-only">Price: </span>${currentPlan.price}
                </span>
                <span className="text-linear-text-secondary transition-all duration-300 ease-in-out">
                  /{currentPlan.period}
                </span>
              </div>
              {isAnnual && (
                <div className="mt-2 transition-all duration-300 ease-in-out">
                  <span className="text-linear-text-tertiary text-sm">
                    ${pricing.annual.monthlyEquivalent}/month when billed annually
                  </span>
                  <div className="text-sm font-medium text-green-500">
                    Save ${pricing.annual.savings} vs monthly billing
                  </div>
                </div>
              )}
              <CardDescription
                id="pricing-description"
                className="text-linear-text-secondary mt-4 text-base"
              >
                Everything you need to track real progress
              </CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="mb-6 space-y-3">
                {features.map((feature, index) => (
                  <li key={index} className="text-linear-text flex items-center">
                    <Check className="mr-3 h-5 w-5 text-white" aria-hidden="true" />
                    <span className="text-sm">{feature}</span>
                  </li>
                ))}
              </ul>
              <Link href="/download/ios">
                <Button
                  className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary focus:ring-linear-purple/50 w-full transition-colors focus:ring-2"
                  aria-describedby="trial-terms"
                >
                  Start 3-Day Free Trial
                </Button>
              </Link>
              <p id="trial-terms" className="text-linear-text-tertiary mt-3 text-center text-xs">
                No credit card required • Cancel anytime
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Integrations Section */}
      <section className="py-16 md:py-24" aria-labelledby="integrations-heading">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl text-center">
            {/* Clean Header */}
            <div className="mb-8">
              <h2
                id="integrations-heading"
                className="text-linear-text mb-2 text-2xl font-semibold sm:text-3xl"
              >
                Integrates with everything
              </h2>
              <p className="text-linear-text-secondary">
                Sync your data seamlessly across all your fitness apps
              </p>
            </div>

            {/* Overlapping Logos Row */}
            <div className="relative mx-auto mb-8 flex items-center justify-center">
              {/* Connection line */}
              <div className="via-linear-border absolute left-1/2 h-px w-64 -translate-x-1/2 bg-gradient-to-r from-transparent to-transparent" />

              {/* Apple Health - Center */}
              <div className="relative z-20 mx-4">
                <div className="border-linear-bg flex h-16 w-16 items-center justify-center rounded-full border-4 bg-gradient-to-br from-red-500 to-pink-500 shadow-xl">
                  <svg className="h-9 w-9 text-white" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm1.5-13h-3v6l5.25 3.15.75-1.23-4.5-2.67V7z" />
                  </svg>
                </div>
                <p className="text-linear-text mt-2 text-sm font-medium">Apple Health</p>
              </div>

              {/* Left side apps */}
              <div className="absolute left-1/2 flex -translate-x-[140px]">
                <div className="relative -mr-3 transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-blue-500 to-blue-600 shadow-lg">
                    <span className="text-xs font-bold text-white">MFP</span>
                  </div>
                </div>
                <div className="relative -mr-3 transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-orange-500 to-orange-600 shadow-lg">
                    <span className="text-xs font-bold text-white">S</span>
                  </div>
                </div>
                <div className="relative transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-blue-600 to-cyan-600 shadow-lg">
                    <span className="text-xs font-bold text-white">G</span>
                  </div>
                </div>
              </div>

              {/* Right side apps */}
              <div className="absolute left-1/2 flex translate-x-[44px]">
                <div className="relative -mr-3 transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-teal-500 to-teal-600 shadow-lg">
                    <span className="text-xs font-bold text-white">F</span>
                  </div>
                </div>
                <div className="relative -mr-3 transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-gray-700 to-gray-800 shadow-lg">
                    <span className="text-xs font-bold text-white">W</span>
                  </div>
                </div>
                <div className="relative transition-transform hover:z-10 hover:-translate-y-1">
                  <div className="border-3 border-linear-bg flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-purple-500 to-purple-600 shadow-lg">
                    <span className="text-xs font-bold text-white">O</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Simple text */}
            <p className="text-linear-text-tertiary text-sm">
              MyFitnessPal • Strava • Garmin • Fitbit • Whoop • Oura • and many more
            </p>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative overflow-hidden py-24 md:py-32">
        {/* Background */}
        <div className="from-linear-purple/5 to-linear-purple/5 absolute inset-0 bg-gradient-to-br via-transparent" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(94,106,210,0.1),transparent)]" />

        <div className="container relative z-10 mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl text-center">
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-8 text-white">
              Ready to get started?
            </Badge>
            <h2 className="text-linear-text mb-6 text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl">
              Start tracking what
              <br />
              <span className="from-linear-text via-linear-purple to-linear-text bg-gradient-to-r bg-clip-text text-transparent">
                really matters
              </span>
            </h2>
            <p className="text-linear-text-secondary mx-auto mb-12 max-w-2xl text-lg leading-relaxed sm:text-xl">
              Join 10,000+ people who&apos;ve discovered the difference accurate body composition
              tracking makes. Stop guessing, start measuring.
            </p>

            <div className="mb-8 flex flex-col justify-center gap-4 sm:flex-row">
              <Link href="/download/ios">
                <Button className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-xl px-8 py-4 text-base font-medium shadow-lg transition-all duration-200 hover:scale-105">
                  Start Tracking Today
                </Button>
              </Link>
              <Link href="/about">
                <Button
                  variant="ghost"
                  className="border-linear-border/50 text-linear-text-secondary hover:bg-linear-border/30 hover:text-linear-text rounded-xl border px-8 py-4 text-base backdrop-blur-sm transition-all"
                >
                  Learn more
                </Button>
              </Link>
            </div>

            <div className="text-linear-text-tertiary flex flex-col items-center justify-center gap-6 text-sm sm:flex-row">
              <div className="flex items-center gap-2">
                <Check className="h-4 w-4 text-white" />
                <span>No credit card required</span>
              </div>
              <div className="flex items-center gap-2">
                <Check className="h-4 w-4 text-white" />
                <span>3-day free trial</span>
              </div>
              <div className="flex items-center gap-2">
                <Check className="h-4 w-4 text-white" />
                <span>Cancel anytime</span>
              </div>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
