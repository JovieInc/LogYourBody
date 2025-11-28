import React from 'react';
import Link from 'next/link';
import { Button } from '@shared-ui/atoms/button';
import { Badge } from '@shared-ui/atoms/badge';
import { ArrowRight, Sparkles, Shield, Clock, Download } from 'lucide-react';
import { APP_CONFIG } from '@/constants/app';

interface PrefooterProps {
  variant?: 'default' | 'minimal' | 'cta';
  className?: string;
}

export function Prefooter({ variant = 'default', className = '' }: PrefooterProps) {
  if (variant === 'minimal') {
    return (
      <section className={`relative py-16 md:py-20 ${className}`}>
        <div className="relative z-10 mx-auto max-w-4xl px-6 text-center">
          <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight md:text-4xl">
            Ready to transform?
          </h2>
          <p className="text-linear-text-secondary mb-8 text-lg">
            Join {APP_CONFIG.metadata.totalUsers} people tracking real progress.
          </p>
          <Link href="/download/ios">
            <Button
              size="lg"
              className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-lg px-8 py-3 text-base font-medium transition-all"
            >
              Start Free Trial
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
          </Link>
        </div>
      </section>
    );
  }

  if (variant === 'cta') {
    return (
      <section className={`relative overflow-hidden py-20 md:py-28 ${className}`}>
        {/* Background effects */}
        <div className="from-linear-purple/10 to-linear-purple/10 absolute inset-0 bg-gradient-to-br via-transparent" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(94,106,210,0.15),transparent)]" />

        <div className="relative z-10 mx-auto max-w-5xl px-6">
          <div className="from-linear-card via-linear-card/95 to-linear-card/90 border-linear-border/50 rounded-3xl border bg-gradient-to-br p-12 text-center backdrop-blur-sm md:p-16">
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-6 inline-flex items-center text-white">
              <Sparkles className="mr-1 h-3 w-3" />
              Limited Time Offer
            </Badge>

            <h2 className="text-linear-text mb-6 text-4xl font-bold tracking-tight md:text-5xl lg:text-6xl">
              Transform your body.
              <br />
              <span className="from-linear-text via-linear-purple to-linear-text bg-gradient-to-r bg-clip-text text-transparent">
                Transform your life.
              </span>
            </h2>

            <p className="text-linear-text-secondary mx-auto mb-10 max-w-2xl text-lg leading-relaxed md:text-xl">
              Professional body composition tracking trusted by {APP_CONFIG.metadata.totalUsers}{' '}
              people worldwide. See what you're really made of.
            </p>

            <div className="mb-8 flex flex-col justify-center gap-4 sm:flex-row">
              <Link href="/download/ios">
                <Button
                  size="lg"
                  className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-xl px-8 py-4 text-base font-medium shadow-lg transition-all duration-200 hover:scale-105"
                >
                  Download for iOS
                  <Download className="ml-2 h-5 w-5" />
                </Button>
              </Link>
              <Link href="/demo">
                <Button
                  size="lg"
                  variant="outline"
                  className="border-linear-border/50 text-linear-text-secondary hover:bg-linear-border/30 hover:text-linear-text rounded-xl px-8 py-4 text-base backdrop-blur-sm transition-all"
                >
                  Watch Demo
                </Button>
              </Link>
            </div>

            <div className="text-linear-text-tertiary flex flex-wrap items-center justify-center gap-6 text-sm">
              <div className="flex items-center gap-2">
                <Shield className="h-4 w-4" />
                <span>Privacy first</span>
              </div>
              <div className="flex items-center gap-2">
                <Clock className="h-4 w-4" />
                <span>{APP_CONFIG.trialLengthText}</span>
              </div>
              <div className="flex items-center gap-2">
                <span>Cancel anytime</span>
              </div>
            </div>
          </div>
        </div>
      </section>
    );
  }

  // Default variant
  return (
    <section
      className={`via-linear-card/30 to-linear-card/50 relative bg-gradient-to-b from-transparent py-20 md:py-24 ${className}`}
    >
      <div className="mx-auto max-w-7xl px-6">
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
          {/* Content */}
          <div>
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-4 inline-block text-white">
              Why LogYourBody?
            </Badge>
            <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight md:text-4xl lg:text-5xl">
              The only tracker that shows
              <br />
              <span className="text-linear-text-secondary">what's really changing</span>
            </h2>
            <p className="text-linear-text-secondary mb-8 text-lg leading-relaxed">
              Stop guessing with just weight. Track body fat percentage, FFMI, and see your actual
              transformation with progress photos that tell the real story.
            </p>

            <div className="mb-8 grid gap-4 sm:grid-cols-2">
              <div className="flex items-start gap-3">
                <div className="bg-linear-purple/20 mt-1 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full">
                  <div className="bg-linear-purple h-2 w-2 rounded-full" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 font-semibold">Professional Accuracy</h3>
                  <p className="text-linear-text-secondary text-sm">
                    Navy, 3-site & 7-site methods
                  </p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="bg-linear-purple/20 mt-1 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full">
                  <div className="bg-linear-purple h-2 w-2 rounded-full" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 font-semibold">Visual Proof</h3>
                  <p className="text-linear-text-secondary text-sm">Automated progress photos</p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="bg-linear-purple/20 mt-1 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full">
                  <div className="bg-linear-purple h-2 w-2 rounded-full" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 font-semibold">Smart Integration</h3>
                  <p className="text-linear-text-secondary text-sm">Syncs with Apple Health</p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="bg-linear-purple/20 mt-1 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full">
                  <div className="bg-linear-purple h-2 w-2 rounded-full" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 font-semibold">Private & Secure</h3>
                  <p className="text-linear-text-secondary text-sm">Your data stays yours</p>
                </div>
              </div>
            </div>

            <div className="flex flex-col gap-4 sm:flex-row">
              <Link href="/download/ios">
                <Button className="bg-linear-purple hover:bg-linear-purple/90 rounded-lg px-6 py-3 text-base font-medium text-white transition-all">
                  Start Tracking Today
                  <ArrowRight className="ml-2 h-5 w-5" />
                </Button>
              </Link>
              <Link href="/about">
                <Button
                  variant="ghost"
                  className="text-linear-text-secondary hover:text-linear-text rounded-lg px-6 py-3 text-base transition-all"
                >
                  Learn More
                </Button>
              </Link>
            </div>
          </div>

          {/* Visual element */}
          <div className="relative lg:pl-12">
            <div className="relative">
              {/* Floating cards representing features */}
              <div className="grid gap-4">
                <div className="border-linear-border/50 bg-linear-card/80 transform rounded-xl border p-6 backdrop-blur-sm transition-transform hover:-translate-y-1">
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-linear-text-secondary text-sm">Body Fat %</span>
                    <Badge className="border-green-500/20 bg-green-500/10 text-green-400">
                      -2.3%
                    </Badge>
                  </div>
                  <div className="text-linear-text text-2xl font-bold">14.5%</div>
                </div>

                <div className="border-linear-border/50 bg-linear-card/80 transform rounded-xl border p-6 backdrop-blur-sm transition-transform hover:-translate-y-1">
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-linear-text-secondary text-sm">FFMI</span>
                    <Badge className="bg-linear-purple/10 border-linear-purple/20 text-white">
                      Natural
                    </Badge>
                  </div>
                  <div className="text-linear-text text-2xl font-bold">23.4</div>
                </div>

                <div className="border-linear-border/50 bg-linear-card/80 transform rounded-xl border p-6 backdrop-blur-sm transition-transform hover:-translate-y-1">
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-linear-text-secondary text-sm">Lean Mass</span>
                    <Badge className="border-blue-500/20 bg-blue-500/10 text-blue-400">
                      +5 lbs
                    </Badge>
                  </div>
                  <div className="text-linear-text text-2xl font-bold">165 lbs</div>
                </div>
              </div>

              {/* Background decoration */}
              <div className="from-linear-purple/20 to-linear-purple/20 absolute -inset-4 -z-10 bg-gradient-to-r via-transparent blur-3xl" />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

export default Prefooter;
