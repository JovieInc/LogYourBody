'use client';

import React from 'react';
import { Badge } from '@shared-ui/atoms/badge';
import { TrendingUp, Clock } from 'lucide-react';

export function LandingPredictionSection() {
  return (
    <section className="via-linear-purple/5 bg-gradient-to-b from-transparent to-transparent py-20 md:py-32">
      <div className="mx-auto max-w-[1280px] px-6">
        <div className="grid gap-16 lg:grid-cols-2 lg:items-center">
          <div>
            <Badge className="bg-linear-purple/10 border-linear-purple/20 mb-4 inline-block text-white">
              Future insights
            </Badge>
            <h2 className="text-linear-text mb-6 text-4xl leading-[1.2] font-bold tracking-tight sm:text-5xl">
              Know your body&apos;s future
            </h2>
            <p className="text-linear-text-secondary mb-8 text-lg sm:text-xl">
              Our prediction engine analyzes every log to forecast how you&apos;ll look if you keep
              your current habits. Catch setbacks early or double down on what&apos;s working.
            </p>
            <div className="space-y-6">
              <div className="flex gap-4">
                <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                  <TrendingUp className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 text-lg font-semibold">
                    Data-driven forecasts
                  </h3>
                  <p className="text-linear-text-secondary">
                    We combine photos, scans, and workout logs into a single trend line.
                  </p>
                </div>
              </div>
              <div className="flex gap-4">
                <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg">
                  <Clock className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h3 className="text-linear-text mb-1 text-lg font-semibold">
                    Change course in time
                  </h3>
                  <p className="text-linear-text-secondary">
                    See your predicted body six months out so the mirror never catches you off
                    guard.
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div className="relative">
            <div className="border-linear-border bg-linear-card rounded-2xl border p-8 shadow-xl">
              <div className="text-center">
                <div className="text-linear-text-secondary mb-2 text-sm">If you stay on track</div>
                <div className="text-linear-text mb-4 text-4xl font-bold">12% BF</div>
                <div className="text-linear-text-tertiary text-sm">in 6 months</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

export default LandingPredictionSection;
