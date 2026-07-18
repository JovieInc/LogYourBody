'use client';

import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Progress } from '@/components/ui/progress';
import { Separator } from '@/components/ui/separator';
import { toast } from '@/hooks/use-toast';
import { APP_CONFIG } from '@/constants/app';
import { Loader2, ArrowLeft, Crown, Check, X, Zap } from 'lucide-react';
import Link from 'next/link';
import { logYourBody } from '@jovieinc/product-registry';

const proPlan = logYourBody.plans[0];
const planFeatureNames = proPlan.featureIds.map(
  (featureId) =>
    logYourBody.features.find((feature) => feature.id === featureId)?.name ?? featureId,
);

export default function SubscriptionSettingsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [selectedPlan, setSelectedPlan] = useState<'monthly' | 'annual'>('annual');

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <Loader2 className="text-linear-text-secondary h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  const handleUpgrade = async () => {
    setIsLoading(true);
    try {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      toast({
        title: 'Upgrade started',
        description: 'Redirecting to payment...',
      });
    } catch {
      toast({
        title: 'Error',
        description: 'Failed to start upgrade. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsLoading(false);
    }
  };

  const plans = {
    monthly: {
      price: APP_CONFIG.pricing.monthly.price,
      period: 'month',
      features: planFeatureNames,
    },
    annual: {
      price: APP_CONFIG.pricing.annual.price,
      period: 'year',
      monthlyPrice: APP_CONFIG.pricing.annual.monthlyEquivalent,
      savings: APP_CONFIG.pricing.annual.savings,
      savingsPercent: APP_CONFIG.pricing.annual.savingsPercent,
      features: planFeatureNames,
    },
  };

  const _currentPlan = selectedPlan === 'annual' ? plans.annual : plans.monthly;
  const trialLengthDays = APP_CONFIG.trialLengthDays;

  // Mock subscription data
  const subscription = {
    status: 'free',
    trialEndsAt: new Date(Date.now() + trialLengthDays * 24 * 60 * 60 * 1000),
    nextBillingDate: null,
    plan: null,
  };

  const daysLeftInTrial = Math.ceil(
    (subscription.trialEndsAt.getTime() - Date.now()) / (1000 * 60 * 60 * 24),
  );

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/settings">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Subscription</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto max-w-4xl space-y-6 px-4 py-6">
        {/* Current Plan */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="text-linear-text">Current Plan</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  Your subscription status and benefits
                </CardDescription>
              </div>
              <Badge variant="secondary" className="text-sm">
                Free Trial
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <Alert className="border-linear-purple/20 bg-linear-purple/5">
              <Zap className="text-linear-purple h-4 w-4" />
              <AlertDescription className="text-linear-text">
                <strong>{daysLeftInTrial} days left</strong> in your free trial. Upgrade now to keep
                all your data and features.
              </AlertDescription>
            </Alert>

            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-linear-text-secondary">Trial Progress</span>
                <span className="text-linear-text font-medium">
                  {trialLengthDays - daysLeftInTrial} of {trialLengthDays} days
                </span>
              </div>
              <Progress
                value={((trialLengthDays - daysLeftInTrial) / trialLengthDays) * 100}
                className="h-2"
              />
            </div>

            <div className="pt-2">
              <p className="text-linear-text-secondary text-sm">
                After your trial ends, you'll be limited to:
              </p>
              <ul className="text-linear-text-secondary mt-2 space-y-1 text-sm">
                <li className="flex items-center gap-2">
                  <X className="h-3 w-3 text-red-500" />
                  View-only access to past data
                </li>
                <li className="flex items-center gap-2">
                  <X className="h-3 w-3 text-red-500" />
                  No new entries or photos
                </li>
                <li className="flex items-center gap-2">
                  <X className="h-3 w-3 text-red-500" />
                  Limited to basic features
                </li>
              </ul>
            </div>
          </CardContent>
        </Card>

        {/* Pricing Plans */}
        <div className="space-y-4">
          <div className="text-center">
            <h2 className="text-linear-text mb-2 text-2xl font-bold">Choose Your Plan</h2>
            <p className="text-linear-text-secondary">
              Full access to all features. Cancel anytime.
            </p>
          </div>

          {/* Plan Toggle */}
          <div className="flex justify-center">
            <div className="bg-linear-card border-linear-border flex rounded-lg border p-1">
              <button
                onClick={() => setSelectedPlan('monthly')}
                className={`rounded-md px-4 py-2 text-sm font-medium transition-colors ${
                  selectedPlan === 'monthly'
                    ? 'bg-linear-purple text-white'
                    : 'text-linear-text-secondary hover:text-linear-text'
                }`}
              >
                Monthly
              </button>
              <button
                onClick={() => setSelectedPlan('annual')}
                className={`rounded-md px-4 py-2 text-sm font-medium transition-colors ${
                  selectedPlan === 'annual'
                    ? 'bg-linear-purple text-white'
                    : 'text-linear-text-secondary hover:text-linear-text'
                }`}
              >
                Annual
                <Badge variant="secondary" className="ml-2 text-xs">
                  Save {plans.annual.savingsPercent}%
                </Badge>
              </button>
            </div>
          </div>

          {/* Plans Grid */}
          <div className="grid gap-6 md:grid-cols-2">
            {/* Monthly Plan */}
            <Card
              className={`bg-linear-card cursor-pointer transition-all ${
                selectedPlan === 'monthly'
                  ? 'border-linear-purple ring-linear-purple/20 ring-2'
                  : 'border-linear-border hover:border-linear-text-tertiary'
              }`}
              onClick={() => setSelectedPlan('monthly')}
            >
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-linear-text">Monthly</CardTitle>
                  {selectedPlan === 'monthly' && (
                    <div className="bg-linear-purple flex h-5 w-5 items-center justify-center rounded-full">
                      <Check className="h-3 w-3 text-white" />
                    </div>
                  )}
                </div>
                <div className="mt-4">
                  <span className="text-linear-text text-3xl font-bold">
                    ${plans.monthly.price}
                  </span>
                  <span className="text-linear-text-secondary">/month</span>
                </div>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2">
                  {plans.monthly.features.map((feature, index) => (
                    <li key={index} className="flex items-start gap-2 text-sm">
                      <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
                      <span className="text-linear-text-secondary">{feature}</span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>

            {/* Annual Plan */}
            <Card
              className={`bg-linear-card relative cursor-pointer transition-all ${
                selectedPlan === 'annual'
                  ? 'border-linear-purple ring-linear-purple/20 ring-2'
                  : 'border-linear-border hover:border-linear-text-tertiary'
              }`}
              onClick={() => setSelectedPlan('annual')}
            >
              <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                <Badge className="bg-linear-purple text-white">BEST VALUE</Badge>
              </div>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-linear-text">Annual</CardTitle>
                  {selectedPlan === 'annual' && (
                    <div className="bg-linear-purple flex h-5 w-5 items-center justify-center rounded-full">
                      <Check className="h-3 w-3 text-white" />
                    </div>
                  )}
                </div>
                <div className="mt-4">
                  <span className="text-linear-text text-3xl font-bold">${plans.annual.price}</span>
                  <span className="text-linear-text-secondary">/year</span>
                </div>
                <p className="mt-1 text-sm text-green-500">
                  Save ${plans.annual.savings} ({plans.annual.savingsPercent}% off)
                </p>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2">
                  {plans.annual.features.map((feature, index) => (
                    <li key={index} className="flex items-start gap-2 text-sm">
                      <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
                      <span className="text-linear-text-secondary">{feature}</span>
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          </div>

          {/* Upgrade Button */}
          <div className="pt-4 text-center">
            <Button
              onClick={handleUpgrade}
              disabled={isLoading}
              size="lg"
              className="bg-linear-purple hover:bg-linear-purple/80 px-8 text-white"
            >
              {isLoading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Processing...
                </>
              ) : (
                <>
                  <Crown className="mr-2 h-4 w-4" />
                  Upgrade to {selectedPlan === 'annual' ? 'Annual' : 'Monthly'}
                </>
              )}
            </Button>
            <p className="text-linear-text-tertiary mt-3 text-xs">
              No commitment. Cancel anytime. Secure payment.
            </p>
          </div>
        </div>

        {/* Features Comparison */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">What's Included</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Everything you need to track your fitness journey
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-3">
                <h4 className="text-linear-text mb-2 font-medium">Core Features</h4>
                <div className="space-y-2">
                  {[
                    'Unlimited weight entries',
                    'Body fat % tracking',
                    'FFMI calculations',
                    'Progress photos',
                    'Apple Health sync',
                    'Data export',
                  ].map((feature) => (
                    <div key={feature} className="flex items-center gap-2 text-sm">
                      <Check className="h-4 w-4 text-green-500" />
                      <span className="text-linear-text-secondary">{feature}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-3">
                <h4 className="text-linear-text mb-2 font-medium">Premium Analytics</h4>
                <div className="space-y-2">
                  {[
                    'Trend predictions',
                    'Weekly reports',
                    'Goal tracking',
                    'Body composition analysis',
                    'Progress insights',
                    'Custom reminders',
                  ].map((feature) => (
                    <div key={feature} className="flex items-center gap-2 text-sm">
                      <Check className="h-4 w-4 text-green-500" />
                      <span className="text-linear-text-secondary">{feature}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* FAQ */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Frequently Asked Questions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <h4 className="text-linear-text mb-1 font-medium">Can I cancel anytime?</h4>
              <p className="text-linear-text-secondary text-sm">
                Yes! You can cancel your subscription at any time. You'll continue to have access
                until the end of your billing period.
              </p>
            </div>

            <Separator className="bg-linear-border" />

            <div>
              <h4 className="text-linear-text mb-1 font-medium">
                What happens to my data if I cancel?
              </h4>
              <p className="text-linear-text-secondary text-sm">
                Your data is always yours. You can export it anytime, and we'll keep it safe for 90
                days after cancellation in case you want to reactivate.
              </p>
            </div>

            <Separator className="bg-linear-border" />

            <div>
              <h4 className="text-linear-text mb-1 font-medium">Do you offer refunds?</h4>
              <p className="text-linear-text-secondary text-sm">
                Purchases, cancellations, and refund requests are managed through your Apple ID and
                follow Apple&apos;s subscription terms.
              </p>
            </div>
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
