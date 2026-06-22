'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Button } from './ui/button';
import { BarChart3, Camera, Smartphone, TrendingUp, Shield, Clock } from 'lucide-react';
import { Footer } from './Footer';
import { Header } from './Header';
import { Prefooter } from './Prefooter';
import { LandingPageFeatureSections } from './LandingPageFeatureSections';
import { LandingPageConversionSections } from './LandingPageConversionSections';

export function LandingPage() {
  const [isAnnual, setIsAnnual] = useState(true); // Default to annual for savings

  const pricing = {
    monthly: {
      price: 9.99,
      period: 'month',
      yearlyTotal: 119.88,
    },
    annual: {
      price: 69.99,
      period: 'year',
      monthlyEquivalent: 5.83,
      savings: 49.89,
      savingsPercent: 42,
    },
  };

  const appFeatures = [
    {
      icon: BarChart3,
      title: 'Body Fat % Tracking',
      description: 'Navy, 3-site, and 7-site methods. Accurate to ±2% when done correctly.',
    },
    {
      icon: TrendingUp,
      title: 'FFMI Calculator',
      description: 'Know your genetic potential. Track lean muscle gains without the guesswork.',
    },
    {
      icon: Camera,
      title: 'Progress Photos',
      description: "Automated reminders. Consistent angles. See changes you'd miss in the mirror.",
    },
    {
      icon: Smartphone,
      title: '1-Tap Import',
      description: 'Pulls weight from Apple Health. No manual entry. Always up to date.',
    },
    {
      icon: Shield,
      title: 'Your Data, Private',
      description:
        'Built for the privacy-obsessed: keep your progress photos under lock and key, where they belong.',
    },
    {
      icon: Clock,
      title: 'Takes 30 Seconds',
      description: 'Log complete body metrics faster than you can tie your shoes.',
    },
  ];

  const currentPlan = isAnnual ? pricing.annual : pricing.monthly;

  const features = [
    'Track body fat % with 3 methods',
    'FFMI & lean mass calculations',
    'Progress photos with reminders',
    'Apple Health & Google Fit sync',
    'Export your data anytime',
    'Weekly progress reports',
    'Trend predictions',
    'No ads, ever',
  ];

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const handleFeatureClick = (featureId: string) => {
    scrollToSection(featureId);
  };

  return (
    <div className="bg-linear-bg font-inter min-h-svh">
      {/* Skip Links */}
      <div className="sr-only z-50 focus:not-sr-only focus:absolute focus:left-4 focus:top-4">
        <button
          className="bg-linear-purple text-linear-text focus:ring-linear-purple/50 rounded px-4 py-2 focus:ring-2"
          onClick={() => document.getElementById('main-content')?.focus()}
        >
          Skip to main content
        </button>
      </div>
      <Header onFeatureClick={handleFeatureClick} showFeatures={true} />

      {/* Main Content */}
      <main id="main-content" tabIndex={-1}>
        {/* Hero Section - YC Style */}
        <section
          className="relative overflow-hidden pb-8 pt-20 md:pb-12 md:pt-24"
          role="banner"
          aria-labelledby="hero-heading"
        >
          {/* Subtle background */}
          <div className="from-linear-purple/5 absolute inset-0 bg-gradient-to-b to-transparent" />

          <div className="container relative z-10 mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-5xl">
              {/* Centered Content - YC Style */}
              <div className="mb-8 text-center">
                {/* Clear Value Prop */}
                <h1
                  id="hero-heading"
                  className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl"
                >
                  Track body fat percentage,
                  <br />
                  not just weight
                </h1>

                {/* One-liner explanation */}
                <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg sm:text-xl">
                  Professional body composition tracking with FFMI calculations and progress photos.
                  Syncs with Apple Health.
                </p>

                {/* Primary CTA - YC style */}
                <div className="mb-6 flex flex-col items-center justify-center gap-4 sm:flex-row">
                  <Link href="/download/ios">
                    <Button className="bg-linear-purple hover:bg-linear-purple/90 rounded-lg px-8 py-3 text-base font-semibold text-white shadow-md transition-all">
                      Start Free Trial
                    </Button>
                  </Link>
                  <Link
                    href="/demo"
                    className="text-linear-text-secondary hover:text-linear-text underline underline-offset-4 transition-colors"
                  >
                    Watch 2-min demo
                  </Link>
                </div>

                {/* Trust indicators */}
                <div className="text-linear-text-tertiary flex flex-wrap items-center justify-center gap-6 text-sm">
                  <span>No credit card required</span>
                  <span>•</span>
                  <span>10,000+ active users</span>
                  <span>•</span>
                  <span>4.9★ App Store</span>
                </div>
              </div>

              {/* Simple Product Visual */}
              <div className="relative mx-auto max-w-3xl">
                <div className="from-linear-card/50 to-linear-card/30 border-linear-border/50 rounded-xl border bg-gradient-to-br p-4 shadow-xl backdrop-blur-sm">
                  <div className="from-linear-purple/10 to-linear-purple/5 border-linear-border/30 flex aspect-[16/9] items-center justify-center rounded-lg border bg-gradient-to-br">
                    <div className="grid grid-cols-3 gap-4 p-8">
                      {/* Mini feature previews */}
                      <div className="text-center">
                        <div className="bg-linear-purple/20 mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-lg">
                          <BarChart3 className="h-6 w-6 text-white" />
                        </div>
                        <p className="text-linear-text-secondary text-xs">BF% Tracking</p>
                      </div>
                      <div className="text-center">
                        <div className="bg-linear-purple/20 mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-lg">
                          <TrendingUp className="h-6 w-6 text-white" />
                        </div>
                        <p className="text-linear-text-secondary text-xs">FFMI Calculator</p>
                      </div>
                      <div className="text-center">
                        <div className="bg-linear-purple/20 mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-lg">
                          <Camera className="h-6 w-6 text-white" />
                        </div>
                        <p className="text-linear-text-secondary text-xs">Progress Photos</p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <LandingPageFeatureSections appFeatures={appFeatures} />

        <LandingPageConversionSections
          features={features}
          isAnnual={isAnnual}
          setIsAnnual={setIsAnnual}
          pricing={pricing}
          currentPlan={currentPlan}
        />
      </main>

      {/* Prefooter - using minimal variant for variety */}
      <Prefooter variant="minimal" />

      {/* Footer */}
      <Footer />
    </div>
  );
}
