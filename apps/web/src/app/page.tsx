'use client'

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ClerkAuthContext';
import { useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  BarChart3,
  Camera,
  Smartphone,
  TrendingUp,
  Shield,
  Clock,
  Check,
  ArrowRight,
  Sparkles,
} from "lucide-react";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { LandingTimelineDemo } from "@/components/LandingTimelineDemo";
import { StepTrackerSection } from "@/components/StepTrackerModule";
import { LandingPredictionSection } from "@/components/LandingPredictionSection";
import { Prefooter } from "@/components/Prefooter";
import { APP_CONFIG } from "@/constants/app";
import { analytics } from "@/lib/analytics";

export default function HomePage() {
  const [isAnnual, setIsAnnual] = useState(true);
  const { user } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (user) {
      router.push('/dashboard');
    }
  }, [user, router]);

  useEffect(() => {
    analytics.track('web_landing_viewed');
  }, []);

  const pricing = APP_CONFIG.pricing;

  const appFeatures = [
    {
      icon: BarChart3,
      title: "Body Composition Analytics",
      description:
        "Professional-grade tracking. See what's actually changing beyond the scale.",
    },
    {
      icon: TrendingUp,
      title: "Aesthetic Intelligence",
      description:
        "FFMI calculations and predictive modeling. Know your peak potential.",
    },
    {
      icon: Camera,
      title: "Visual Progress System",
      description:
        "Consistent angles. Side-by-side comparisons. The truth in pixels.",
    },
    {
      icon: Smartphone,
      title: "Unified Data Pipeline",
      description:
        "Import DEXA scans, smart scales, Apple Health. One source of truth.",
    },
    {
      icon: Shield,
      title: "Privacy First",
      description:
        "Built for the privacy-obsessed: keep your progress photos under lock and key, where they belong.",
    },
    {
      icon: Clock,
      title: "Efficiency Engineered",
      description:
        "Log complete metrics in 30 seconds. Spend your time in the gym, not the app.",
    },
  ];

  const currentPlan = isAnnual ? pricing.annual : pricing.monthly;

  const features = [
    "Professional body composition tracking",
    "FFMI & aesthetic potential analysis",
    "Automated progress photo system",
    "Multi-source data import",
    "Predictive trend modeling",
    "Weekly transformation reports",
    "Export everything, anytime",
    "Zero ads, ever",
  ];

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: "smooth" });
    }
  };

  const handleFeatureClick = (featureId: string) => {
    scrollToSection(featureId);
  };

  return (
    <div className="min-h-screen bg-[#08090a] font-inter">
      <Header onFeatureClick={handleFeatureClick} showFeatures={true} />

      {/* Main Content */}
      <main id="main-content" tabIndex={-1}>
        {/* Hero Section - Linear Style */}
        <section
          className="relative pt-32 pb-20"
          role="banner"
          aria-labelledby="hero-heading"
        >
          <div className="max-w-6xl mx-auto px-6">
            <div className="text-center">
              {/* Hero Content */}
              <div className="max-w-4xl mx-auto">
                <h1
                  id="hero-heading"
                  className="text-5xl md:text-6xl lg:text-7xl font-bold tracking-tight text-white mb-6 leading-[1.05]"
                >
                  Track your body.
                  <br />
                  Transform your life.
                </h1>

                <p className="text-xl md:text-2xl text-white/60 mb-10 max-w-2xl mx-auto leading-[1.5] font-normal">
                  Professional body composition tracking that shows you exactly how you're transforming.
                </p>

                {/* CTAs - Linear Style */}
                <div className="flex flex-col sm:flex-row gap-4 justify-center mb-12">
                  <Link href="/download/ios">
                    <Button
                      size="lg"
                      className="bg-white text-black px-8 py-6 text-base font-medium rounded-full hover:bg-white/90 transition-all shadow-2xl"
                      onClick={() => analytics.track('web_cta_clicked', { id: 'download_ios' })}
                    >
                      Download for iOS
                    </Button>
                  </Link>
                  <Link href="#timeline-feature">
                    <Button
                      size="lg"
                      variant="outline"
                      className="border-white/10 text-white hover:bg-white/5 px-8 py-6 text-base rounded-full"
                      onClick={() => analytics.track('web_cta_clicked', { id: 'see_it_in_action' })}
                    >
                      See it in action
                    </Button>
                  </Link>
                </div>

                {/* Trust indicators - Linear Style */}
                <div className="flex flex-wrap items-center justify-center gap-6 text-sm text-white/40">
                  <div className="flex items-center gap-2">
                    <Check className="h-4 w-4" />
                    <span>Free to try</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Check className="h-4 w-4" />
                    <span>{APP_CONFIG.metadata.totalUsers} users</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Check className="h-4 w-4" />
                    <span>{APP_CONFIG.metadata.appStoreRating}★ App Store</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* AI Auto-Edit Section */}
        <section className="py-20 bg-gradient-to-b from-transparent to-white/[0.02]">
          <div className="max-w-6xl mx-auto px-6">
            <div className="text-center mb-16">
              <Badge variant="secondary" className="mb-4 bg-purple-500/10 text-purple-400 border-purple-500/20">
                <Sparkles className="h-3 w-3 mr-1" />
                AI-Powered Feature
              </Badge>
              <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                Zero-Click Progress Photos
              </h2>
              <p className="text-xl text-white/60 max-w-2xl mx-auto">
                Upload once. Our AI-AutoEdit™ instantly crops, aligns, color-corrects & removes backgrounds for flawless, uniform shots—every time.
              </p>
            </div>

            {/* Feature showcase */}
            <div className="rounded-2xl bg-gradient-to-b from-white/5 to-transparent border border-white/10 p-8 md:p-12">
              <div className="grid md:grid-cols-2 gap-12 items-center">
                <div>
                  <h3 className="text-2xl font-semibold text-white mb-6">
                    Why We're Different
                  </h3>
                  <ul className="space-y-4 text-lg">
                    <li className="flex items-start gap-3">
                      <Check className="h-5 w-5 text-purple-400 mt-1" />
                      <span className="text-white/80">
                        <strong className="text-white">No Manual Cropping</strong>—perfection happens automatically
                      </span>
                    </li>
                    <li className="flex items-start gap-3">
                      <Check className="h-5 w-5 text-purple-400 mt-1" />
                      <span className="text-white/80">
                        <strong className="text-white">Consistent Angles</strong>—AI ensures perfect alignment every time
                      </span>
                    </li>
                    <li className="flex items-start gap-3">
                      <Check className="h-5 w-5 text-purple-400 mt-1" />
                      <span className="text-white/80">
                        <strong className="text-white">Privacy First</strong>—optional "Remove Originals" deletes photos from camera roll
                      </span>
                    </li>
                    <li className="flex items-start gap-3">
                      <Check className="h-5 w-5 text-purple-400 mt-1" />
                      <span className="text-white/80">
                        <strong className="text-white">Face Blurring (Coming Soon)</strong>—protect your identity while tracking progress
                      </span>
                    </li>
                  </ul>
                </div>
                <div className="relative">
                  {/* Visual representation */}
                  <div className="aspect-square bg-gradient-to-br from-purple-500/20 to-purple-600/10 rounded-2xl border border-purple-500/20 flex items-center justify-center">
                    <div className="text-center">
                      <Camera className="h-16 w-16 text-purple-400 mx-auto mb-4" />
                      <p className="text-white/60">AI-powered photo processing</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Social Proof */}
        <section className="py-16 border-y border-[#1a1b1e]">
          <div className="max-w-[1280px] mx-auto px-6">
            <div className="mb-12 text-center">
              <p className="text-sm text-white/50 mb-6">Trusted by fitness professionals and aesthetic athletes worldwide</p>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
              <div className="group">
                <div className="text-4xl md:text-5xl font-bold mb-2 text-white">
                  {APP_CONFIG.metadata.totalUsers}
                </div>
                <div className="text-sm text-white/70">Active transformations</div>
              </div>
              <div className="group">
                <div className="text-4xl md:text-5xl font-bold mb-2 text-white">
                  {APP_CONFIG.metadata.successRate}
                </div>
                <div className="text-sm text-white/70">Hit their goals</div>
              </div>
              <div className="group">
                <div className="text-4xl md:text-5xl font-bold mb-2 text-white">
                  {APP_CONFIG.metadata.appStoreRating}/5
                </div>
                <div className="text-sm text-white/70">App Store rating</div>
              </div>
              <div className="group">
                <div className="text-4xl md:text-5xl font-bold mb-2 text-white">
                  30s
                </div>
                <div className="text-sm text-white/70">Average log time</div>
              </div>
            </div>
          </div>
        </section>

        {/* Features Grid */}
        <section className="py-20">
          <div className="max-w-[1280px] mx-auto px-6">
            <div className="text-center mb-16">
              <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                Everything you need. Nothing you don't.
              </h2>
              <p className="text-xl text-white/60 max-w-2xl mx-auto">
                Professional tools designed for serious transformations.
              </p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
              {appFeatures.map((feature, index) => (
                <Card
                  key={index}
                  className="bg-[#0f1011] border-[#1a1b1e] hover:border-[#2a2b2e] transition-all group"
                >
                  <CardHeader>
                    <div className="mb-4 p-3 bg-[#1a1b1e] rounded-lg w-fit group-hover:bg-[#2a2b2e] transition-colors">
                      <feature.icon className="h-6 w-6 text-white" />
                    </div>
                    <CardTitle className="text-white text-xl">
                      {feature.title}
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <CardDescription className="text-white/60 text-base">
                      {feature.description}
                    </CardDescription>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        {/* Interactive Demo Section */}
        <section
          id="timeline-feature"
          className="py-20 bg-gradient-to-b from-transparent to-[#0f1011]"
          aria-labelledby="timeline-heading"
        >
          <div className="max-w-[1280px] mx-auto px-6">
            <div className="text-center mb-16">
              <h2 id="timeline-heading" className="text-4xl md:text-5xl font-bold text-white mb-4">
                See your transformation unfold
              </h2>
              <p className="text-xl text-white/60 max-w-2xl mx-auto">
                Track every milestone. Visualize your journey. Celebrate your progress.
              </p>
            </div>
            <LandingTimelineDemo />
          </div>
        </section>

        {/* Step Tracker Section */}
        <section id="steps-feature" className="py-20">
          <StepTrackerSection />
        </section>

        {/* Prediction Section */}
        <section className="py-20 bg-gradient-to-b from-[#0f1011] to-transparent">
          <LandingPredictionSection />
        </section>

        {/* Pricing Section */}
        <section id="pricing" className="py-20">
          <div className="max-w-[1280px] mx-auto px-6">
            <div className="text-center mb-16">
              <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                Start your transformation today
              </h2>
              <p className="text-xl text-white/60 max-w-2xl mx-auto mb-8">
                Join thousands achieving their ideal physique with professional tracking.
              </p>

              {/* Pricing Toggle */}
              <div className="inline-flex items-center gap-4 p-1 bg-[#1a1b1e] rounded-full">
                <button
                  onClick={() => setIsAnnual(false)}
                  className={`px-6 py-2 rounded-full text-sm font-medium transition-all ${!isAnnual
                      ? 'bg-white text-black'
                      : 'text-white/60 hover:text-white'
                    }`}
                >
                  Monthly
                </button>
                <button
                  onClick={() => setIsAnnual(true)}
                  className={`px-6 py-2 rounded-full text-sm font-medium transition-all ${isAnnual
                      ? 'bg-white text-black'
                      : 'text-white/60 hover:text-white'
                    }`}
                >
                  Annual
                  {isAnnual && (
                    <Badge className="ml-2 bg-green-500/20 text-green-400 border-0">
                      Save {APP_CONFIG.pricing.annual.savingsPercent}%
                    </Badge>
                  )}
                </button>
              </div>
            </div>

            {/* Pricing Card */}
            <div className="max-w-md mx-auto">
              <Card className="bg-[#0f1011] border-[#1a1b1e] relative overflow-hidden">
                {isAnnual && (
                  <div className="absolute top-0 right-0 bg-green-500 text-white text-xs px-3 py-1 rounded-bl-lg">
                    BEST VALUE
                  </div>
                )}
                <CardHeader className="text-center pb-8">
                  <div className="mb-4">
                    <span className="text-5xl font-bold text-white">
                      ${currentPlan.price}
                    </span>
                    <span className="text-white/60 ml-2">/{currentPlan.period}</span>
                  </div>
                  {isAnnual && (
                    <p className="text-sm text-white/60">
                      Just ${APP_CONFIG.pricing.annual.monthlyEquivalent}/month
                    </p>
                  )}
                </CardHeader>
                <CardContent className="space-y-6">
                  <ul className="space-y-4">
                    {features.map((feature, index) => (
                      <li key={index} className="flex items-start gap-3">
                        <Check className="h-5 w-5 text-green-500 mt-0.5" />
                        <span className="text-white/80">{feature}</span>
                      </li>
                    ))}
                  </ul>

                  <Link href="/download/ios" className="block">
                    <Button className="w-full bg-white text-black hover:bg-white/90 py-6 text-base font-medium">
                      Start Free Trial
                      <ArrowRight className="ml-2 h-5 w-5" />
                    </Button>
                  </Link>

                  <p className="text-center text-sm text-white/50">
                    {APP_CONFIG.trialLengthText}. Cancel anytime.
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* Final CTA */}
        <section className="py-20 border-t border-[#1a1b1e]">
          <div className="max-w-4xl mx-auto px-6 text-center">
            <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">
              Ready to see what you're really made of?
            </h2>
            <p className="text-xl text-white/60 mb-10 max-w-2xl mx-auto">
              Professional body composition tracking. Real results. Private and secure.
            </p>
            <Link href="/download/ios">
              <Button
                size="lg"
                className="bg-white text-black px-8 py-6 text-base font-medium rounded-full hover:bg-white/90 transition-all shadow-2xl"
              >
                Download LogYourBody
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
            </Link>
          </div>
        </section>
      </main>

      {/* Prefooter - showcasing the new component */}
      <Prefooter variant="default" />

      <Footer />
    </div>
  );
}