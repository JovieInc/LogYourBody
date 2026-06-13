'use client';

import { useState, useEffect } from 'react';
// import Image from 'next/image'
// import Link from 'next/link'
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import {
  Apple,
  Star,
  CheckCircle2,
  Camera,
  TrendingUp,
  Shield,
  Zap,
  Users,
  Award,
  ArrowRight,
  ChevronRight,
  Clock,
  Target,
  Heart,
  Sparkles,
} from 'lucide-react';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';

export default function IOSDownloadPage() {
  const [isIOS, setIsIOS] = useState(false);
  const [showAppStoreRedirect, setShowAppStoreRedirect] = useState(false);
  const appStoreRedirectHref = '/api/app-store-redirect?platform=ios&source=landing';

  useEffect(() => {
    // Detect if user is on iOS
    const userAgent = navigator.userAgent || navigator.vendor;
    const isIOSDevice = /iPad|iPhone|iPod/.test(userAgent) && !('MSStream' in window);
    setIsIOS(isIOSDevice);
  }, []);

  const handleDownload = () => {
    setShowAppStoreRedirect(true);
  };

  const coreFeatures = [
    {
      icon: Target,
      title: 'FFMI Tracking',
      description: 'Know your genetic potential. Track lean muscle without the guesswork.',
      stat: '±0.1 accuracy',
    },
    {
      icon: Camera,
      title: 'Progress Photos',
      description: 'AI-powered background removal. Consistent angles. See real changes.',
      stat: '92% stick to it',
    },
    {
      icon: Clock,
      title: '30-Second Logging',
      description: 'Navy method calculations. Apple Health sync. Done before your coffee cools.',
      stat: '10x faster',
    },
  ];

  const trustSignals = [
    { value: '4.9★', label: 'App Store Rating' },
    { value: '10K+', label: 'Active Users' },
    { value: '500K+', label: 'Measurements Logged' },
    { value: '99.9%', label: 'Uptime' },
  ];

  const comparisonData = [
    { feature: 'FFMI Calculator', us: true, others: false },
    { feature: 'Progress Photo AI', us: true, others: false },
    { feature: 'Apple Health Sync', us: true, others: 'partial' },
    { feature: 'Trend Predictions', us: true, others: false },
    { feature: 'Privacy First', us: true, others: false },
    { feature: 'No Ads Ever', us: true, others: false },
    { feature: 'Expert Support', us: true, others: false },
    { feature: 'Offline Mode', us: true, others: 'partial' },
  ];

  const testimonials = [
    {
      name: 'Dr. Sarah Chen',
      role: 'Sports Medicine',
      content:
        'Finally, an app that tracks what actually matters for body composition. I recommend it to all my patients.',
      avatar: '👩‍⚕️',
    },
    {
      name: 'Mike Rodriguez',
      role: 'Natural Bodybuilder',
      content:
        'The FFMI tracking helped me understand my genetic limits. Game changer for natural athletes.',
      avatar: '💪',
    },
    {
      name: 'Emma Wilson',
      role: 'Fitness Coach',
      content:
        'My clients love the progress photos feature. Seeing changes they miss in the mirror keeps them motivated.',
      avatar: '🏃‍♀️',
    },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white">
      <Header />

      {/* Hero Section - Apple-inspired */}
      <section className="relative overflow-hidden pb-32 pt-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl text-center">
            {/* App Store Badge */}
            <div className="mb-8 inline-flex items-center justify-center">
              <Badge className="border-blue-200 bg-blue-50 px-4 py-2 text-blue-700">
                <Apple className="mr-2 h-4 w-4" />
                Exclusively on iPhone
              </Badge>
            </div>

            {/* Main Headline - Apple copywriting style */}
            <h1 className="mb-6 text-5xl font-bold tracking-tight text-gray-900 sm:text-6xl md:text-7xl">
              Your body.
              <br />
              <span className="bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
                Decoded.
              </span>
            </h1>

            <p className="mx-auto mb-10 max-w-2xl text-xl leading-relaxed text-gray-600">
              The only app that tracks FFMI, body fat percentage, and progress photos with
              scientific accuracy. Know exactly where you stand.
            </p>

            {/* Primary CTA */}
            <div className="mb-8">
              <Button
                asChild
                className="w-full max-w-sm rounded-2xl bg-black px-4 py-6 text-base font-medium text-white shadow-2xl transition-all duration-200 hover:scale-105 hover:bg-gray-900 sm:w-auto sm:px-10 sm:text-lg"
              >
                <a
                  href={appStoreRedirectHref}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={handleDownload}
                >
                  <Apple className="mr-3 h-6 w-6" />
                  Download on the App Store
                  <ArrowRight className="ml-3 h-5 w-5" />
                </a>
              </Button>

              {isIOS && <p className="mt-4 text-sm text-gray-500">Opens in App Store</p>}
            </div>

            {/* Trust Signals */}
            <div className="flex flex-wrap items-center justify-center gap-6 text-sm text-gray-600">
              <div className="flex items-center gap-1">
                {[...Array(5)].map((_, i) => (
                  <Star key={i} className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                ))}
                <span className="ml-2 font-medium">4.9 on App Store</span>
              </div>
              <div className="flex items-center gap-2">
                <Users className="h-4 w-4 text-gray-400" />
                <span>10K+ active users</span>
              </div>
              <div className="flex items-center gap-2">
                <Shield className="h-4 w-4 text-gray-400" />
                <span>Privacy first</span>
              </div>
            </div>
          </div>
        </div>

        {/* Background decoration */}
        <div className="absolute inset-0 -z-10">
          <div className="absolute left-10 top-20 h-72 w-72 rounded-full bg-blue-100 opacity-20 blur-3xl filter"></div>
          <div className="absolute bottom-20 right-10 h-96 w-96 rounded-full bg-purple-100 opacity-20 blur-3xl filter"></div>
        </div>
      </section>

      {/* Core Features - Linear.app style */}
      <section className="bg-white py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mb-16 text-center">
            <h2 className="mb-4 text-3xl font-bold text-gray-900 sm:text-4xl">
              Built for serious athletes
            </h2>
            <p className="mx-auto max-w-2xl text-xl text-gray-600">
              Stop guessing. Start knowing. Track what actually matters.
            </p>
          </div>

          <div className="mx-auto grid max-w-5xl gap-8 md:grid-cols-3">
            {coreFeatures.map((feature, index) => {
              const IconComponent = feature.icon;
              return (
                <div
                  key={index}
                  className="group relative rounded-2xl border border-gray-100 bg-gray-50 p-8 transition-all duration-300 hover:bg-white hover:shadow-xl"
                >
                  <div className="mb-6">
                    <div className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-blue-500 to-purple-500 text-white shadow-lg">
                      <IconComponent className="h-7 w-7" />
                    </div>
                  </div>

                  <h3 className="mb-3 text-xl font-bold text-gray-900">{feature.title}</h3>

                  <p className="mb-4 leading-relaxed text-gray-600">{feature.description}</p>

                  <div className="flex items-center text-sm font-medium text-blue-600">
                    <Sparkles className="mr-2 h-4 w-4" />
                    {feature.stat}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* iPhone Mockup Section */}
      <section className="bg-gray-50 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-2">
            {/* Content */}
            <div className="order-2 lg:order-1">
              <Badge className="mb-6 border-green-200 bg-green-50 text-green-700">
                <Zap className="mr-2 h-3 w-3" />
                Lightning Fast
              </Badge>

              <h2 className="mb-6 text-4xl font-bold text-gray-900">
                Log in seconds.
                <br />
                Track for life.
              </h2>

              <div className="mb-8 space-y-4">
                <div className="flex items-start gap-3">
                  <CheckCircle2 className="mt-0.5 h-6 w-6 flex-shrink-0 text-green-500" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Smart Calculations</h4>
                    <p className="text-gray-600">
                      Navy method auto-calculates body fat percentage from measurements
                    </p>
                  </div>
                </div>

                <div className="flex items-start gap-3">
                  <CheckCircle2 className="mt-0.5 h-6 w-6 flex-shrink-0 text-green-500" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Apple Health Sync</h4>
                    <p className="text-gray-600">
                      Weight automatically pulled from your Apple Watch or smart scale
                    </p>
                  </div>
                </div>

                <div className="flex items-start gap-3">
                  <CheckCircle2 className="mt-0.5 h-6 w-6 flex-shrink-0 text-green-500" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Progress Photos</h4>
                    <p className="text-gray-600">
                      AI removes background for perfect before/after comparisons
                    </p>
                  </div>
                </div>
              </div>

              <Button
                asChild
                className="w-full max-w-xs rounded-xl bg-black px-4 py-4 text-white transition-all hover:bg-gray-900 sm:w-auto sm:px-8"
              >
                <a
                  href={appStoreRedirectHref}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={handleDownload}
                >
                  Get Started Free
                  <ChevronRight className="ml-2 h-5 w-5" />
                </a>
              </Button>
            </div>

            {/* iPhone Mockup */}
            <div className="relative order-1 lg:order-2">
              <div className="relative mx-auto h-[640px] w-80">
                {/* Phone Frame */}
                <div className="absolute inset-0 rounded-[3rem] bg-gray-900 shadow-2xl"></div>

                {/* Screen */}
                <div className="absolute inset-3 overflow-hidden rounded-[2.5rem] bg-white">
                  {/* Status Bar */}
                  <div className="flex h-14 items-center justify-between bg-gray-50 px-8 pt-2">
                    <span className="text-xs font-medium">9:41</span>
                    <div className="flex items-center gap-1">
                      <div className="h-3 w-6 rounded-sm border border-gray-400">
                        <div className="h-full w-4 rounded-sm bg-gray-400"></div>
                      </div>
                    </div>
                  </div>

                  {/* App UI */}
                  <div className="px-6 py-4">
                    <h3 className="mb-6 text-2xl font-bold text-gray-900">Dashboard</h3>

                    {/* FFMI Card */}
                    <div className="mb-4 rounded-2xl bg-gradient-to-r from-blue-500 to-purple-500 p-6 text-white">
                      <div className="mb-4 flex items-start justify-between">
                        <div>
                          <p className="mb-1 text-sm text-blue-100">Fat-Free Mass Index</p>
                          <p className="text-4xl font-bold">21.4</p>
                        </div>
                        <Badge className="border-white/30 bg-white/20 text-white">Excellent</Badge>
                      </div>
                      <div className="text-sm text-blue-100">
                        87th percentile for natural athletes
                      </div>
                    </div>

                    {/* Stats Grid */}
                    <div className="mb-4 grid grid-cols-2 gap-3">
                      <div className="rounded-xl bg-gray-50 p-4">
                        <p className="mb-1 text-xs text-gray-500">Body Fat</p>
                        <p className="text-2xl font-bold text-gray-900">12.3%</p>
                        <p className="text-xs text-green-600">↓ 0.5%</p>
                      </div>
                      <div className="rounded-xl bg-gray-50 p-4">
                        <p className="mb-1 text-xs text-gray-500">Weight</p>
                        <p className="text-2xl font-bold text-gray-900">180 lbs</p>
                        <p className="text-xs text-gray-500">→ 0.0</p>
                      </div>
                    </div>

                    {/* Action Button */}
                    <Button className="w-full rounded-xl bg-gray-900 py-4 text-white">
                      Log New Measurement
                    </Button>
                  </div>
                </div>

                {/* Notch */}
                <div className="absolute left-1/2 top-3 h-7 w-40 -translate-x-1/2 transform rounded-full bg-gray-900"></div>
              </div>

              {/* Floating elements */}
              <div className="absolute -right-4 -top-4 rounded-2xl border border-gray-100 bg-white p-4 shadow-xl">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-full bg-green-100">
                    <TrendingUp className="h-5 w-5 text-green-600" />
                  </div>
                  <div>
                    <p className="text-xs text-gray-500">Weekly Progress</p>
                    <p className="text-lg font-bold text-gray-900">+2.3%</p>
                  </div>
                </div>
              </div>

              <div className="absolute -bottom-4 -left-4 rounded-2xl border border-gray-100 bg-white p-4 shadow-xl">
                <div className="flex items-center gap-3">
                  <Award className="h-8 w-8 text-yellow-500" />
                  <div>
                    <p className="text-xs text-gray-500">Streak</p>
                    <p className="text-lg font-bold text-gray-900">45 days</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Comparison Table */}
      <section className="bg-white py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl">
            <div className="mb-12 text-center">
              <h2 className="mb-4 text-3xl font-bold text-gray-900 sm:text-4xl">
                Why professionals choose LogYourBody
              </h2>
              <p className="text-xl text-gray-600">
                See how we stack up against generic fitness apps
              </p>
            </div>

            <div className="overflow-hidden rounded-2xl bg-gray-50">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="p-6 text-left font-medium text-gray-600">Feature</th>
                    <th className="p-6 text-center">
                      <div className="inline-flex items-center justify-center">
                        <span className="font-bold text-blue-600">LogYourBody</span>
                      </div>
                    </th>
                    <th className="p-6 text-center text-gray-400">Others</th>
                  </tr>
                </thead>
                <tbody>
                  {comparisonData.map((row, index) => (
                    <tr key={index} className="border-b border-gray-100">
                      <td className="p-6 text-gray-700">{row.feature}</td>
                      <td className="p-6 text-center">
                        {row.us === true ? (
                          <CheckCircle2 className="mx-auto h-6 w-6 text-green-500" />
                        ) : (
                          <span className="text-gray-400">{row.us}</span>
                        )}
                      </td>
                      <td className="p-6 text-center">
                        {row.others === true ? (
                          <CheckCircle2 className="mx-auto h-6 w-6 text-green-500" />
                        ) : row.others === false ? (
                          <div className="mx-auto h-6 w-6 rounded-full bg-gray-200"></div>
                        ) : (
                          <span className="text-sm text-gray-400">{row.others}</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="bg-gray-50 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-5xl">
            <div className="mb-12 text-center">
              <h2 className="mb-4 text-3xl font-bold text-gray-900 sm:text-4xl">
                Trusted by experts and athletes
              </h2>
              <p className="text-xl text-gray-600">
                Join thousands who&apos;ve discovered smarter body composition tracking
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-3">
              {testimonials.map((testimonial, index) => (
                <Card key={index} className="border-gray-200 transition-shadow hover:shadow-lg">
                  <CardContent className="p-6">
                    <div className="mb-4 flex items-center gap-1">
                      {[...Array(5)].map((_, i) => (
                        <Star key={i} className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                      ))}
                    </div>

                    <p className="mb-6 leading-relaxed text-gray-700">
                      &quot;{testimonial.content}&quot;
                    </p>

                    <div className="flex items-center gap-3">
                      <div className="text-3xl">{testimonial.avatar}</div>
                      <div>
                        <div className="font-semibold text-gray-900">{testimonial.name}</div>
                        <div className="text-sm text-gray-500">{testimonial.role}</div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="bg-gradient-to-r from-blue-600 to-purple-600 py-20 text-white">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto grid max-w-4xl grid-cols-2 gap-8 md:grid-cols-4">
            {trustSignals.map((stat, index) => (
              <div key={index} className="text-center">
                <div className="mb-2 text-4xl font-bold">{stat.value}</div>
                <div className="text-blue-100">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="bg-white py-24">
        <div className="container mx-auto px-4 text-center sm:px-6">
          <div className="mx-auto max-w-3xl">
            <h2 className="mb-6 text-4xl font-bold text-gray-900 sm:text-5xl">
              Start tracking what matters
            </h2>
            <p className="mb-10 text-xl text-gray-600">
              Join thousands of athletes who&apos;ve stopped guessing and started knowing. Download
              LogYourBody and see your true progress.
            </p>

            <Button
              asChild
              className="w-full max-w-sm rounded-2xl bg-black px-4 py-6 text-base font-medium text-white shadow-2xl transition-all duration-200 hover:scale-105 hover:bg-gray-900 sm:w-auto sm:px-12 sm:text-lg"
            >
              <a
                href={appStoreRedirectHref}
                target="_blank"
                rel="noopener noreferrer"
                onClick={handleDownload}
              >
                <Apple className="mr-3 h-6 w-6" />
                Download Free on App Store
                <ArrowRight className="ml-3 h-5 w-5" />
              </a>
            </Button>

            <div className="mt-8 flex items-center justify-center gap-8 text-sm text-gray-500">
              <div className="flex items-center gap-2">
                <Heart className="h-4 w-4 text-red-500" />
                No ads, ever
              </div>
              <div className="flex items-center gap-2">
                <Shield className="h-4 w-4 text-green-500" />
                Your data stays private
              </div>
              <div className="flex items-center gap-2">
                <Zap className="h-4 w-4 text-yellow-500" />
                Cancel anytime
              </div>
            </div>
          </div>
        </div>
      </section>

      <Footer />

      {/* App Store Redirect Modal */}
      {showAppStoreRedirect && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-8">
            <div className="text-center">
              <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-100">
                <Apple className="h-8 w-8 text-blue-600" />
              </div>
              <h3 className="mb-2 text-2xl font-bold text-gray-900">Opening App Store...</h3>
              <p className="mb-6 text-gray-600">
                You&apos;re being redirected to download LogYourBody
              </p>
              <Button
                onClick={() => setShowAppStoreRedirect(false)}
                variant="outline"
                className="w-full"
              >
                Close
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
