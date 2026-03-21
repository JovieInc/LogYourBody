'use client';

import { useState, useEffect, useMemo } from 'react';
import Image from 'next/image';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { BodyFatScale } from '@/components/BodyFatScale';
import { TimelineSlider } from '@/app/dashboard/components/TimelineSlider';
import { calculateFFMI, convertWeight } from '@/utils/body-calculations';
import { getAvatarAltText, getAvatarUrl } from '@/utils/avatar-utils';
import { createTimelineData, getTimelineDisplayValues } from '@/utils/data-interpolation';
import type { BodyMetrics, UserProfile } from '@/types/body-metrics';
// import { Card } from '@/components/ui/card'
import {
  Apple,
  CheckCircle2,
  ArrowRight,
  Zap,
  Shield,
  Camera,
  TrendingUp,
  Sparkles,
  QrCode,
  Bell,
  Target,
  Timer,
  Hand,
  TouchpadOff,
  Home,
  Plus,
  Settings,
} from 'lucide-react';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { cn } from '@/lib/utils';

const demoProfile: UserProfile = {
  id: 'demo-user',
  email: 'tim@example.com',
  full_name: 'Tim',
  gender: 'male',
  height: 71,
  height_unit: 'ft',
  email_verified: true,
  onboarding_completed: true,
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: '2026-03-20T00:00:00.000Z',
  settings: {
    units: {
      weight: 'lbs',
      height: 'ft',
      measurements: 'in',
    },
  },
};

const demoMetrics: BodyMetrics[] = [
  {
    id: 'demo-metric-1',
    user_id: demoProfile.id,
    date: '2026-01-12T07:30:00.000Z',
    weight: 84.4,
    weight_unit: 'kg',
    body_fat_percentage: 18.4,
    body_fat_method: 'navy',
    created_at: '2026-01-12T07:30:00.000Z',
    updated_at: '2026-01-12T07:30:00.000Z',
  },
  {
    id: 'demo-metric-2',
    user_id: demoProfile.id,
    date: '2026-02-09T07:30:00.000Z',
    weight: 83.0,
    weight_unit: 'kg',
    body_fat_percentage: 16.2,
    body_fat_method: 'navy',
    created_at: '2026-02-09T07:30:00.000Z',
    updated_at: '2026-02-09T07:30:00.000Z',
  },
  {
    id: 'demo-metric-3',
    user_id: demoProfile.id,
    date: '2026-03-20T07:30:00.000Z',
    weight: 81.6,
    weight_unit: 'kg',
    body_fat_percentage: 13.1,
    body_fat_method: 'navy',
    created_at: '2026-03-20T07:30:00.000Z',
    updated_at: '2026-03-20T07:30:00.000Z',
  },
];

function ProductPhonePreview() {
  const timeline = useMemo(() => createTimelineData(demoMetrics, [], demoProfile.height), []);
  const [selectedDateIndex, setSelectedDateIndex] = useState(timeline.length - 1);

  const currentEntry = timeline[selectedDateIndex];
  const rawValues = currentEntry ? getTimelineDisplayValues(currentEntry) : null;
  const displayWeight = rawValues?.weight
    ? convertWeight(rawValues.weight, 'kg', demoProfile.settings.units?.weight || 'lbs')
    : undefined;
  const ffmi =
    rawValues?.weight && rawValues.bodyFatPercentage && demoProfile.height
      ? calculateFFMI(rawValues.weight, demoProfile.height * 2.54, rawValues.bodyFatPercentage)
          .normalized_ffmi
      : undefined;
  const avatarUrl =
    getAvatarUrl(demoProfile.gender, rawValues?.bodyFatPercentage, 'png') ??
    getAvatarUrl(demoProfile.gender, rawValues?.bodyFatPercentage, 'svg');

  return (
    <div className="relative mx-auto w-72 lg:w-80">
      <div className="absolute inset-0 bg-gradient-to-r from-blue-600/20 to-purple-600/20 blur-3xl" />
      <div className="relative rounded-[3rem] border border-gray-800 bg-gray-900 p-2 shadow-2xl">
        <div className="rounded-[2.5rem] bg-black p-4">
          <div className="bg-linear-bg text-linear-text relative h-[600px] overflow-hidden rounded-[2rem]">
            <div className="flex items-center justify-between px-5 pb-4 pt-3 text-xs">
              <span className="font-medium text-white/70">9:41</span>
              <div className="flex items-center gap-2">
                <div className="h-2 w-2 rounded-full bg-emerald-400" />
                <span className="text-white/50">Synced</span>
              </div>
            </div>

            <div className="absolute left-1/2 top-3 h-7 w-32 -translate-x-1/2 rounded-full bg-black" />

            <div className="border-linear-border flex items-center justify-between border-b px-4 py-3">
              <div>
                <p className="text-linear-text-tertiary text-xs uppercase tracking-[0.18em]">
                  Dashboard
                </p>
                <h3 className="text-linear-text text-base font-semibold">LogYourBody</h3>
              </div>
              <button
                type="button"
                aria-label="Settings preview"
                className="bg-linear-card text-linear-text-secondary flex h-9 w-9 items-center justify-center rounded-full"
              >
                <Settings className="h-4 w-4" />
              </button>
            </div>

            <div className="border-linear-border bg-linear-card grid grid-cols-2 border-b text-sm">
              <div className="border-linear-purple text-linear-text border-b-2 px-4 py-3 text-center font-medium">
                Body Model
              </div>
              <div className="text-linear-text-secondary px-4 py-3 text-center">Photo</div>
            </div>

            <div className="px-4 pt-4">
              <div className="border-linear-border bg-linear-card rounded-2xl border">
                <div className="bg-linear-bg flex h-[190px] items-center justify-center overflow-hidden rounded-t-2xl p-4">
                  {avatarUrl ? (
                    <Image
                      src={avatarUrl}
                      alt={getAvatarAltText(demoProfile.gender, rawValues?.bodyFatPercentage)}
                      width={180}
                      height={240}
                      className="h-full w-auto object-contain"
                      priority
                    />
                  ) : (
                    <div className="text-linear-text-secondary text-sm">No body model</div>
                  )}
                </div>

                <div className="space-y-4 p-4">
                  <div className="grid grid-cols-3 gap-2">
                    <div className="border-linear-border bg-linear-bg rounded-xl border p-3 text-center">
                      <div className="text-linear-text-secondary text-[10px] uppercase tracking-wider">
                        Weight
                      </div>
                      <div className="text-linear-text mt-1 text-xl font-bold">
                        {displayWeight?.toFixed(1) || '--'}
                      </div>
                      <div className="text-linear-text-tertiary text-[11px]">lbs</div>
                    </div>
                    <div className="border-linear-border bg-linear-bg rounded-xl border p-3 text-center">
                      <div className="text-linear-text-secondary text-[10px] uppercase tracking-wider">
                        Body Fat
                      </div>
                      <div className="text-linear-text mt-1 text-xl font-bold">
                        {rawValues?.bodyFatPercentage?.toFixed(1) || '--'}
                      </div>
                      <div className="text-linear-text-tertiary text-[11px]">%</div>
                    </div>
                    <div className="border-linear-border bg-linear-bg rounded-xl border p-3 text-center">
                      <div className="text-linear-text-secondary text-[10px] uppercase tracking-wider">
                        FFMI
                      </div>
                      <div className="text-linear-text mt-1 text-xl font-bold">
                        {ffmi?.toFixed(1) || '--'}
                      </div>
                      <div className="text-linear-text-tertiary text-[11px]">normalized</div>
                    </div>
                  </div>

                  <div>
                    <div className="mb-2 flex items-center justify-between text-xs">
                      <span className="text-linear-text">Body Fat Goal</span>
                      <Badge className="border-linear-purple/30 bg-linear-purple/10 text-linear-purple">
                        Live scale
                      </Badge>
                    </div>
                    <BodyFatScale
                      currentBF={rawValues?.bodyFatPercentage}
                      gender={demoProfile.gender}
                      className="origin-top scale-[0.92]"
                    />
                  </div>
                </div>
              </div>
            </div>

            <div className="mt-4">
              <TimelineSlider
                timeline={timeline}
                selectedIndex={selectedDateIndex}
                onIndexChange={setSelectedDateIndex}
              />
            </div>

            <div className="border-linear-border bg-linear-bg absolute bottom-0 left-0 right-0 border-t">
              <div className="flex h-14 items-center justify-around px-4">
                <div className="text-linear-purple flex flex-1 items-center justify-center">
                  <Home className="h-5 w-5" />
                </div>
                <div className="mx-2 flex flex-1 items-center justify-center">
                  <div className="bg-linear-purple flex h-11 w-11 items-center justify-center rounded-full text-white shadow-lg">
                    <Plus className="h-5 w-5" />
                  </div>
                </div>
                <div className="text-linear-text-secondary flex flex-1 items-center justify-center">
                  <Settings className="h-5 w-5" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function MobilePage() {
  // const [isIOS, setIsIOS] = useState(false)
  const [showQR, setShowQR] = useState(false);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const userAgent = navigator.userAgent || navigator.vendor;
    // const isIOSDevice = /iPad|iPhone|iPod/.test(userAgent) && !(window as any).MSStream
    const isMobileDevice = /iPhone|iPad|iPod|Android/i.test(userAgent);

    // setIsIOS(isIOSDevice)
    setIsMobile(isMobileDevice);
    // Show QR code by default on desktop
    setShowQR(!isMobileDevice);
  }, []);

  const handleDownload = () => {
    window.open('/api/app-store-redirect?platform=ios&source=mobile', '_blank');
  };

  const features = [
    {
      icon: Camera,
      title: 'Screenshot to track',
      description: 'Snap any scale reading. Our AI extracts and logs the numbers instantly.',
    },
    {
      icon: Bell,
      title: 'Smart reminders',
      description: 'Available 24/7. Or just 9-5. Notifications that respect your schedule.',
    },
    {
      icon: TouchpadOff,
      title: 'Tap to log',
      description: 'Body metrics in 30 seconds. Swipe to see trends. No fluff.',
    },
    {
      icon: Target,
      title: 'Palm-perfect design',
      description: 'Every button, every gesture optimized for one-handed use.',
    },
  ];

  const workflows = [
    {
      title: 'Morning weigh-in',
      time: '7:00 AM',
      description: 'Step on scale. Open app. Weight synced. Body fat calculated.',
      icon: Timer,
    },
    {
      title: 'Progress photo',
      time: '7:30 AM',
      description: 'AI-guided angles. Background removed. Side-by-side comparison ready.',
      icon: Camera,
    },
    {
      title: 'Evening review',
      time: '10:00 PM',
      description: "FFMI trend analyzed. Tomorrow's targets set. Sleep confident.",
      icon: TrendingUp,
    },
  ];

  const techSpecs = [
    {
      icon: Zap,
      title: 'Fully native',
      value: 'Swift',
      description: 'Buttery smooth 120fps animations on ProMotion displays',
      color: 'text-orange-500',
    },
    {
      icon: Shield,
      title: 'Privacy first',
      value: 'On-device',
      description: 'Photo processing happens locally. Your data never leaves without encryption',
      color: 'text-green-500',
    },
    {
      icon: Sparkles,
      title: 'AI-powered',
      value: 'CoreML',
      description: 'Instant body fat calculations. Smart meal suggestions. Predictive insights',
      color: 'text-purple-500',
    },
  ];

  return (
    <div className="min-h-screen bg-black text-white">
      <Header />

      {/* Hero Section - Linear Mobile Style */}
      <section className="relative overflow-hidden pb-20 pt-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="grid items-center gap-16 lg:grid-cols-2">
            {/* Left Content */}
            <div className="text-center lg:text-left">
              <h1 className="mb-6 text-5xl font-bold tracking-tight sm:text-6xl lg:text-7xl">
                Introducing
                <br />
                <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                  LogYourBody
                </span>
                <br />
                Mobile
              </h1>

              <p className="mx-auto mb-8 max-w-xl text-xl leading-relaxed text-gray-400 sm:text-2xl lg:mx-0">
                Complex body composition tracking
                <br />
                in compact form.
              </p>

              <div className="mb-12 flex flex-col justify-center gap-4 sm:flex-row lg:justify-start">
                <Button
                  onClick={handleDownload}
                  className="flex items-center justify-center gap-3 rounded-xl bg-white px-8 py-6 text-lg font-medium text-black shadow-2xl transition-all duration-200 hover:bg-gray-100"
                >
                  <Apple className="h-6 w-6" />
                  Download for iPhone
                  <ArrowRight className="h-5 w-5" />
                </Button>

                <Button
                  variant="outline"
                  className="rounded-xl border-gray-800 px-8 py-6 text-lg text-gray-400 hover:bg-gray-900"
                  disabled
                >
                  Android Coming Soon
                </Button>
              </div>

              {/* QR Code Section - Desktop Only */}
              {!isMobile && (
                <div className="hidden lg:block">
                  <div className="inline-flex items-start gap-6 rounded-2xl border border-gray-800 bg-gray-900/50 p-6 backdrop-blur-xl">
                    <div className="text-left">
                      <p className="mb-1 text-sm text-gray-500">Scan to download</p>
                      <p className="text-lg font-medium">Point your iPhone camera here</p>
                    </div>
                    <div className="rounded-xl bg-white p-4">
                      {/* QR Code pointing to App Store */}
                      <svg width="120" height="120" viewBox="0 0 120 120" className="text-black">
                        <rect width="120" height="120" fill="white" />
                        {/* This is a placeholder - in production, use a real QR code generator */}
                        <path
                          d="M10 10h20v20h-20zM40 10h10v10h-10zM60 10h10v10h-10zM80 10h10v10h-10zM90 10h20v20h-20zM10 40h10v10h-10zM30 40h20v10h-20zM60 40h10v10h-10zM80 40h10v10h-10zM100 40h10v10h-10zM10 60h10v10h-10zM30 60h10v10h-10zM50 60h20v10h-20zM80 60h10v10h-10zM100 60h10v10h-10zM10 80h10v10h-10zM30 80h20v10h-20zM60 80h10v10h-10zM80 80h10v10h-10zM100 80h10v10h-10zM10 90h20v20h-20zM40 100h10v10h-10zM60 100h10v10h-10zM80 100h10v10h-10zM90 90h20v20h-20z"
                          fill="currentColor"
                        />
                      </svg>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Right - iPhone using real product UI */}
            <div className="relative mx-auto max-w-sm lg:max-w-none">
              <ProductPhonePreview />
            </div>
          </div>
        </div>
      </section>

      {/* Stay on top Section - Linear Style */}
      <section className="border-t border-gray-900 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl">
            <div className="mb-16 text-center">
              <h2 className="mb-4 text-4xl font-bold sm:text-5xl">
                Stay on top of your most
                <br />
                important body metrics
              </h2>
              <p className="text-xl text-gray-400">
                Your pocket body composition lab. Always ready when you are.
              </p>
            </div>

            {/* Inbox Feature */}
            <div className="mb-8 rounded-2xl border border-gray-800 bg-gray-900/50 p-8">
              <div className="flex items-start gap-6">
                <div className="flex-shrink-0">
                  <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-600/20">
                    <Bell className="h-8 w-8 text-blue-500" />
                  </div>
                </div>
                <div className="flex-1">
                  <h3 className="mb-3 text-2xl font-bold">Inbox</h3>
                  <p className="mb-6 text-lg text-gray-400">
                    Never miss a measurement. Smart reminders adapt to your schedule.
                  </p>
                  <div className="flex flex-wrap gap-3">
                    <Badge className="border-gray-700 bg-gray-800 px-4 py-2 text-gray-300">
                      <TouchpadOff className="mr-2 inline h-3 w-3" />
                      Tap to log
                    </Badge>
                    <Badge className="border-gray-700 bg-gray-800 px-4 py-2 text-gray-300">
                      <Hand className="mr-2 inline h-3 w-3" />
                      Swipe to dismiss
                    </Badge>
                    <Badge className="border-gray-700 bg-gray-800 px-4 py-2 text-gray-300">
                      <Timer className="mr-2 inline h-3 w-3" />
                      Snooze for later
                    </Badge>
                  </div>
                </div>
              </div>
            </div>

            {/* Features Grid */}
            <div className="grid gap-6 sm:grid-cols-2">
              {features.map((feature, index) => {
                const IconComponent = feature.icon;
                return (
                  <div
                    key={index}
                    className="group rounded-xl border border-transparent p-6 transition-all hover:border-gray-800 hover:bg-gray-900/50"
                  >
                    <div className="flex gap-4">
                      <div className="flex-shrink-0">
                        <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gray-900 transition-colors group-hover:bg-gray-800">
                          <IconComponent className="h-6 w-6 text-gray-400" />
                        </div>
                      </div>
                      <div>
                        <h3 className="mb-2 text-lg font-semibold">{feature.title}</h3>
                        <p className="leading-relaxed text-gray-400">{feature.description}</p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Workflows Section */}
      <section className="border-t border-gray-900 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl">
            <div className="mb-16 text-center">
              <Badge className="mb-4 border-gray-800 bg-gray-900 text-gray-400">
                Ultraportable
              </Badge>
              <h2 className="mb-4 text-4xl font-bold sm:text-5xl">Designed for real life</h2>
              <p className="text-xl text-gray-400">From morning weigh-in to evening review</p>
            </div>

            <div className="space-y-4">
              {workflows.map((workflow, index) => {
                const IconComponent = workflow.icon;
                return (
                  <div
                    key={index}
                    className="flex gap-6 rounded-2xl border border-gray-800 bg-gray-900/30 p-6 transition-all hover:border-gray-700 hover:bg-gray-900/50"
                  >
                    <div className="flex-shrink-0">
                      <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-gray-800 to-gray-900">
                        <IconComponent className="h-6 w-6 text-gray-300" />
                      </div>
                    </div>
                    <div className="flex-1">
                      <div className="mb-2 flex items-start justify-between">
                        <h3 className="text-lg font-semibold">{workflow.title}</h3>
                        <span className="text-sm text-gray-500">{workflow.time}</span>
                      </div>
                      <p className="text-gray-400">{workflow.description}</p>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Tech Specs - Linear Style */}
      <section className="border-t border-gray-900 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-6xl">
            <div className="mb-16 text-center">
              <h2 className="mb-4 text-4xl font-bold sm:text-5xl">Built different</h2>
              <p className="text-xl text-gray-400">
                Native performance. Privacy by design. AI at the edge.
              </p>
            </div>

            <div className="grid gap-8 lg:grid-cols-3">
              {techSpecs.map((spec, index) => {
                const IconComponent = spec.icon;
                return (
                  <div key={index} className="text-center">
                    <div className="mb-6 inline-block">
                      <IconComponent className={cn('h-12 w-12', spec.color)} />
                    </div>
                    <h3 className="mb-2 text-2xl font-bold">{spec.title}</h3>
                    <div className="mb-4 font-mono text-3xl text-gray-400">{spec.value}</div>
                    <p className="leading-relaxed text-gray-400">{spec.description}</p>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Availability Section */}
      <section className="border-t border-gray-900 py-20">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl text-center">
            <h2 className="mb-4 text-4xl font-bold sm:text-5xl">
              Available 24/7.
              <br />
              <span className="text-gray-400">Or just 9-5.</span>
            </h2>
            <p className="mx-auto mb-12 max-w-2xl text-xl text-gray-400">
              Configure notification schedules that respect your time. Track on your terms, not
              ours.
            </p>

            <div className="inline-block rounded-2xl border border-gray-800 bg-gray-900/50 p-8">
              <div className="mb-6 grid grid-cols-7 gap-4">
                {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) => (
                  <div key={day} className="text-center">
                    <p className="mb-2 text-xs text-gray-500">{day}</p>
                    <div
                      className={cn(
                        'h-16 w-12 rounded-lg',
                        day === 'Sat' || day === 'Sun'
                          ? 'bg-gray-800'
                          : 'bg-gradient-to-b from-blue-600 to-purple-600',
                      )}
                    ></div>
                  </div>
                ))}
              </div>
              <p className="text-sm text-gray-400">
                Weekday mornings only • Perfect for your routine
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="border-t border-gray-900 py-24">
        <div className="container mx-auto px-4 text-center sm:px-6">
          <div className="mx-auto max-w-3xl">
            <h2 className="mb-6 text-5xl font-bold sm:text-6xl lg:text-7xl">
              Your pocket
              <br />
              body comp lab
            </h2>
            <p className="mb-10 text-xl text-gray-400">
              Start tracking what matters. Available now on iPhone.
            </p>

            <div className="mb-12 flex flex-col justify-center gap-4 sm:flex-row">
              <Button
                onClick={handleDownload}
                className="rounded-xl bg-white px-10 py-6 text-lg font-medium text-black shadow-2xl transition-all duration-200 hover:bg-gray-100"
              >
                <Apple className="mr-3 h-6 w-6" />
                Download on App Store
              </Button>

              {!isMobile && (
                <Button
                  variant="outline"
                  onClick={() => setShowQR(!showQR)}
                  className="rounded-xl border-gray-800 px-10 py-6 text-lg text-gray-400 hover:bg-gray-900"
                >
                  <QrCode className="mr-3 h-6 w-6" />
                  {showQR ? 'Hide' : 'Show'} QR Code
                </Button>
              )}
            </div>

            {/* QR Code Modal */}
            {showQR && !isMobile && (
              <div className="mb-12 inline-block rounded-2xl border border-gray-800 bg-gray-900 p-8">
                <p className="mb-4 text-sm text-gray-500">Scan with your iPhone camera</p>
                <div className="rounded-xl bg-white p-6">
                  <svg width="200" height="200" viewBox="0 0 200 200" className="text-black">
                    <rect width="200" height="200" fill="white" />
                    {/* Placeholder QR pattern */}
                    <path
                      d="M20 20h40v40h-40zM140 20h40v40h-40zM20 140h40v40h-40zM80 20h20v20h-20zM100 40h20v20h-20zM80 60h20v20h-20zM100 80h20v20h-20zM80 100h20v20h-20zM100 120h20v20h-20zM80 140h20v20h-20zM140 80h20v20h-20zM160 100h20v20h-20zM140 120h20v20h-20z"
                      fill="currentColor"
                    />
                  </svg>
                </div>
                <p className="mt-4 text-xs text-gray-500">Takes you straight to the App Store</p>
              </div>
            )}

            <div className="flex items-center justify-center gap-8 text-sm text-gray-500">
              <div className="flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-green-500" />
                Free to try
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-green-500" />
                No ads, ever
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-green-500" />
                Cancel anytime
              </div>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
