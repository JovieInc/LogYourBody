'use client'

import { useState, useEffect } from 'react'
// import Image from 'next/image'
// import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
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
} from 'lucide-react'
import { Header } from '@/components/Header'
import { Footer } from '@/components/Footer'

export default function IOSDownloadPage() {
  const [isIOS, setIsIOS] = useState(false)
  const [showAppStoreRedirect, setShowAppStoreRedirect] = useState(false)

  useEffect(() => {
    // Detect if user is on iOS
    const userAgent = navigator.userAgent || navigator.vendor
    const isIOSDevice = /iPad|iPhone|iPod/.test(userAgent) && !('MSStream' in window)
    setIsIOS(isIOSDevice)
  }, [])

  const handleDownload = () => {
    setShowAppStoreRedirect(true)
    // Track conversion event via API
    window.open('/api/app-store-redirect?platform=ios&source=landing', '_blank')
  }

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
  ]

  const trustSignals = [
    { value: '4.9★', label: 'App Store Rating' },
    { value: '10K+', label: 'Active Users' },
    { value: '500K+', label: 'Measurements Logged' },
    { value: '99.9%', label: 'Uptime' },
  ]

  const comparisonData = [
    { feature: 'FFMI Calculator', us: true, others: false },
    { feature: 'Progress Photo AI', us: true, others: false },
    { feature: 'Apple Health Sync', us: true, others: 'partial' },
    { feature: 'Trend Predictions', us: true, others: false },
    { feature: 'Privacy First', us: true, others: false },
    { feature: 'No Ads Ever', us: true, others: false },
    { feature: 'Expert Support', us: true, others: false },
    { feature: 'Offline Mode', us: true, others: 'partial' },
  ]

  const testimonials = [
    {
      name: 'Dr. Sarah Chen',
      role: 'Sports Medicine',
      content: 'Finally, an app that tracks what actually matters for body composition. I recommend it to all my patients.',
      avatar: '👩‍⚕️',
    },
    {
      name: 'Mike Rodriguez',
      role: 'Natural Bodybuilder',
      content: 'The FFMI tracking helped me understand my genetic limits. Game changer for natural athletes.',
      avatar: '💪',
    },
    {
      name: 'Emma Wilson',
      role: 'Fitness Coach',
      content: 'My clients love the progress photos feature. Seeing changes they miss in the mirror keeps them motivated.',
      avatar: '🏃‍♀️',
    },
  ]

  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white">
      <Header />

      {/* Hero Section - Apple-inspired */}
      <section className="relative overflow-hidden pt-20 pb-32">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-4xl text-center">
            {/* App Store Badge */}
            <div className="mb-8 inline-flex items-center justify-center">
              <Badge className="bg-blue-50 text-blue-700 border-blue-200 px-4 py-2">
                <Apple className="h-4 w-4 mr-2" />
                Exclusively on iPhone
              </Badge>
            </div>

            {/* Main Headline - Apple copywriting style */}
            <h1 className="mb-6 text-5xl sm:text-6xl md:text-7xl font-bold tracking-tight text-gray-900">
              Your body.<br />
              <span className="bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
                Decoded.
              </span>
            </h1>

            <p className="mx-auto mb-10 max-w-2xl text-xl text-gray-600 leading-relaxed">
              The only app that tracks FFMI, body fat percentage, and progress photos 
              with scientific accuracy. Know exactly where you stand.
            </p>

            {/* Primary CTA */}
            <div className="mb-8">
              <Button
                onClick={handleDownload}
                className="bg-black text-white px-10 py-6 text-lg font-medium rounded-2xl hover:bg-gray-900 transition-all duration-200 hover:scale-105 shadow-2xl"
              >
                <Apple className="h-6 w-6 mr-3" />
                Download on the App Store
                <ArrowRight className="h-5 w-5 ml-3" />
              </Button>
              
              {isIOS && (
                <p className="mt-4 text-sm text-gray-500">
                  Opens in App Store
                </p>
              )}
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
          <div className="absolute top-20 left-10 w-72 h-72 bg-blue-100 rounded-full filter blur-3xl opacity-20"></div>
          <div className="absolute bottom-20 right-10 w-96 h-96 bg-purple-100 rounded-full filter blur-3xl opacity-20"></div>
        </div>
      </section>

      {/* Core Features - Linear.app style */}
      <section className="py-20 bg-white">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mb-16 text-center">
            <h2 className="mb-4 text-3xl sm:text-4xl font-bold text-gray-900">
              Built for serious athletes
            </h2>
            <p className="text-xl text-gray-600 max-w-2xl mx-auto">
              Stop guessing. Start knowing. Track what actually matters.
            </p>
          </div>

          <div className="grid gap-8 md:grid-cols-3 max-w-5xl mx-auto">
            {coreFeatures.map((feature, index) => {
              const IconComponent = feature.icon
              return (
                <div
                  key={index}
                  className="group relative bg-gray-50 rounded-2xl p-8 hover:bg-white hover:shadow-xl transition-all duration-300 border border-gray-100"
                >
                  <div className="mb-6">
                    <div className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-blue-500 to-purple-500 text-white shadow-lg">
                      <IconComponent className="h-7 w-7" />
                    </div>
                  </div>
                  
                  <h3 className="mb-3 text-xl font-bold text-gray-900">
                    {feature.title}
                  </h3>
                  
                  <p className="mb-4 text-gray-600 leading-relaxed">
                    {feature.description}
                  </p>
                  
                  <div className="flex items-center text-sm font-medium text-blue-600">
                    <Sparkles className="h-4 w-4 mr-2" />
                    {feature.stat}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* iPhone Mockup Section */}
      <section className="py-20 bg-gray-50">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="grid lg:grid-cols-2 gap-12 items-center max-w-6xl mx-auto">
            {/* Content */}
            <div className="order-2 lg:order-1">
              <Badge className="mb-6 bg-green-50 text-green-700 border-green-200">
                <Zap className="h-3 w-3 mr-2" />
                Lightning Fast
              </Badge>
              
              <h2 className="mb-6 text-4xl font-bold text-gray-900">
                Log in seconds.<br />
                Track for life.
              </h2>
              
              <div className="space-y-4 mb-8">
                <div className="flex items-start gap-3">
                  <CheckCircle2 className="h-6 w-6 text-green-500 mt-0.5 flex-shrink-0" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Smart Calculations</h4>
                    <p className="text-gray-600">Navy method auto-calculates body fat percentage from measurements</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <CheckCircle2 className="h-6 w-6 text-green-500 mt-0.5 flex-shrink-0" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Apple Health Sync</h4>
                    <p className="text-gray-600">Weight automatically pulled from your Apple Watch or smart scale</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <CheckCircle2 className="h-6 w-6 text-green-500 mt-0.5 flex-shrink-0" />
                  <div>
                    <h4 className="font-semibold text-gray-900">Progress Photos</h4>
                    <p className="text-gray-600">AI removes background for perfect before/after comparisons</p>
                  </div>
                </div>
              </div>
              
              <Button
                onClick={handleDownload}
                className="bg-black text-white px-8 py-4 rounded-xl hover:bg-gray-900 transition-all"
              >
                Get Started Free
                <ChevronRight className="h-5 w-5 ml-2" />
              </Button>
            </div>

            {/* iPhone Mockup */}
            <div className="order-1 lg:order-2 relative">
              <div className="relative mx-auto w-80 h-[640px]">
                {/* Phone Frame */}
                <div className="absolute inset-0 bg-gray-900 rounded-[3rem] shadow-2xl"></div>
                
                {/* Screen */}
                <div className="absolute inset-3 bg-white rounded-[2.5rem] overflow-hidden">
                  {/* Status Bar */}
                  <div className="h-14 bg-gray-50 flex items-center justify-between px-8 pt-2">
                    <span className="text-xs font-medium">9:41</span>
                    <div className="flex items-center gap-1">
                      <div className="w-6 h-3 border border-gray-400 rounded-sm">
                        <div className="w-4 h-full bg-gray-400 rounded-sm"></div>
                      </div>
                    </div>
                  </div>
                  
                  {/* App UI */}
                  <div className="px-6 py-4">
                    <h3 className="text-2xl font-bold text-gray-900 mb-6">Dashboard</h3>
                    
                    {/* FFMI Card */}
                    <div className="bg-gradient-to-r from-blue-500 to-purple-500 text-white rounded-2xl p-6 mb-4">
                      <div className="flex justify-between items-start mb-4">
                        <div>
                          <p className="text-blue-100 text-sm mb-1">Fat-Free Mass Index</p>
                          <p className="text-4xl font-bold">21.4</p>
                        </div>
                        <Badge className="bg-white/20 text-white border-white/30">
                          Excellent
                        </Badge>
                      </div>
                      <div className="text-sm text-blue-100">
                        87th percentile for natural athletes
                      </div>
                    </div>
                    
                    {/* Stats Grid */}
                    <div className="grid grid-cols-2 gap-3 mb-4">
                      <div className="bg-gray-50 rounded-xl p-4">
                        <p className="text-gray-500 text-xs mb-1">Body Fat</p>
                        <p className="text-2xl font-bold text-gray-900">12.3%</p>
                        <p className="text-xs text-green-600">↓ 0.5%</p>
                      </div>
                      <div className="bg-gray-50 rounded-xl p-4">
                        <p className="text-gray-500 text-xs mb-1">Weight</p>
                        <p className="text-2xl font-bold text-gray-900">180 lbs</p>
                        <p className="text-xs text-gray-500">→ 0.0</p>
                      </div>
                    </div>
                    
                    {/* Action Button */}
                    <Button className="w-full bg-gray-900 text-white rounded-xl py-4">
                      Log New Measurement
                    </Button>
                  </div>
                </div>
                
                {/* Notch */}
                <div className="absolute top-3 left-1/2 transform -translate-x-1/2 w-40 h-7 bg-gray-900 rounded-full"></div>
              </div>
              
              {/* Floating elements */}
              <div className="absolute -top-4 -right-4 bg-white rounded-2xl shadow-xl p-4 border border-gray-100">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 bg-green-100 rounded-full flex items-center justify-center">
                    <TrendingUp className="h-5 w-5 text-green-600" />
                  </div>
                  <div>
                    <p className="text-xs text-gray-500">Weekly Progress</p>
                    <p className="text-lg font-bold text-gray-900">+2.3%</p>
                  </div>
                </div>
              </div>
              
              <div className="absolute -bottom-4 -left-4 bg-white rounded-2xl shadow-xl p-4 border border-gray-100">
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
      <section className="py-20 bg-white">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-4xl mx-auto">
            <div className="text-center mb-12">
              <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">
                Why professionals choose LogYourBody
              </h2>
              <p className="text-xl text-gray-600">
                See how we stack up against generic fitness apps
              </p>
            </div>

            <div className="bg-gray-50 rounded-2xl overflow-hidden">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="text-left p-6 text-gray-600 font-medium">Feature</th>
                    <th className="text-center p-6">
                      <div className="inline-flex items-center justify-center">
                        <span className="text-blue-600 font-bold">LogYourBody</span>
                      </div>
                    </th>
                    <th className="text-center p-6 text-gray-400">Others</th>
                  </tr>
                </thead>
                <tbody>
                  {comparisonData.map((row, index) => (
                    <tr key={index} className="border-b border-gray-100">
                      <td className="p-6 text-gray-700">{row.feature}</td>
                      <td className="text-center p-6">
                        {row.us === true ? (
                          <CheckCircle2 className="h-6 w-6 text-green-500 mx-auto" />
                        ) : (
                          <span className="text-gray-400">{row.us}</span>
                        )}
                      </td>
                      <td className="text-center p-6">
                        {row.others === true ? (
                          <CheckCircle2 className="h-6 w-6 text-green-500 mx-auto" />
                        ) : row.others === false ? (
                          <div className="h-6 w-6 mx-auto rounded-full bg-gray-200"></div>
                        ) : (
                          <span className="text-gray-400 text-sm">{row.others}</span>
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
      <section className="py-20 bg-gray-50">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-5xl mx-auto">
            <div className="text-center mb-12">
              <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">
                Trusted by experts and athletes
              </h2>
              <p className="text-xl text-gray-600">
                Join thousands who&apos;ve discovered smarter body composition tracking
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-3">
              {testimonials.map((testimonial, index) => (
                <Card key={index} className="border-gray-200 hover:shadow-lg transition-shadow">
                  <CardContent className="p-6">
                    <div className="flex items-center gap-1 mb-4">
                      {[...Array(5)].map((_, i) => (
                        <Star key={i} className="h-4 w-4 fill-yellow-400 text-yellow-400" />
                      ))}
                    </div>
                    
                    <p className="text-gray-700 mb-6 leading-relaxed">
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
      <section className="py-20 bg-gradient-to-r from-blue-600 to-purple-600 text-white">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto">
            {trustSignals.map((stat, index) => (
              <div key={index} className="text-center">
                <div className="text-4xl font-bold mb-2">{stat.value}</div>
                <div className="text-blue-100">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-24 bg-white">
        <div className="container mx-auto px-4 sm:px-6 text-center">
          <div className="max-w-3xl mx-auto">
            <h2 className="text-4xl sm:text-5xl font-bold text-gray-900 mb-6">
              Start tracking what matters
            </h2>
            <p className="text-xl text-gray-600 mb-10">
              Join thousands of athletes who&apos;ve stopped guessing and started knowing. 
              Download LogYourBody and see your true progress.
            </p>
            
            <Button
              onClick={handleDownload}
              className="bg-black text-white px-12 py-6 text-lg font-medium rounded-2xl hover:bg-gray-900 transition-all duration-200 hover:scale-105 shadow-2xl"
            >
              <Apple className="h-6 w-6 mr-3" />
              Download Free on App Store
              <ArrowRight className="h-5 w-5 ml-3" />
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
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-8 max-w-md w-full">
            <div className="text-center">
              <div className="h-16 w-16 bg-blue-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
                <Apple className="h-8 w-8 text-blue-600" />
              </div>
              <h3 className="text-2xl font-bold text-gray-900 mb-2">
                Opening App Store...
              </h3>
              <p className="text-gray-600 mb-6">
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
  )
}
