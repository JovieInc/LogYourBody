'use client'

import { useState, useEffect } from 'react'
// import Image from 'next/image'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
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
  Activity,
  Timer,
  Hand,
  TouchpadOff,
} from 'lucide-react'
import { Header } from '@/components/Header'
import { Footer } from '@/components/Footer'
import { cn } from '@/lib/utils'

export default function MobilePage() {
  // const [isIOS, setIsIOS] = useState(false)
  const [showQR, setShowQR] = useState(false)
  const [isMobile, setIsMobile] = useState(false)

  useEffect(() => {
    const userAgent = navigator.userAgent || navigator.vendor
    // const isIOSDevice = /iPad|iPhone|iPod/.test(userAgent) && !(window as any).MSStream
    const isMobileDevice = /iPhone|iPad|iPod|Android/i.test(userAgent)
    
    // setIsIOS(isIOSDevice)
    setIsMobile(isMobileDevice)
    // Show QR code by default on desktop
    setShowQR(!isMobileDevice)
  }, [])

  const handleDownload = () => {
    window.open('/api/app-store-redirect?platform=ios&source=mobile', '_blank')
  }

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
  ]

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
      description: 'FFMI trend analyzed. Tomorrow\'s targets set. Sleep confident.',
      icon: TrendingUp,
    },
  ]

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
  ]

  return (
    <div className="min-h-screen bg-black text-white">
      <Header />

      {/* Hero Section - Linear Mobile Style */}
      <section className="relative pt-32 pb-20 overflow-hidden">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="grid lg:grid-cols-2 gap-16 items-center">
            {/* Left Content */}
            <div className="text-center lg:text-left">
              <h1 className="text-5xl sm:text-6xl lg:text-7xl font-bold mb-6 tracking-tight">
                Introducing
                <br />
                <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                  LogYourBody
                </span>
                <br />
                Mobile
              </h1>
              
              <p className="text-xl sm:text-2xl text-gray-400 mb-8 leading-relaxed max-w-xl mx-auto lg:mx-0">
                Complex body composition tracking
                <br />
                in compact form.
              </p>

              <div className="flex flex-col sm:flex-row gap-4 justify-center lg:justify-start mb-12">
                <Button
                  onClick={handleDownload}
                  className="bg-white text-black px-8 py-6 text-lg font-medium rounded-xl hover:bg-gray-100 transition-all duration-200 flex items-center justify-center gap-3 shadow-2xl"
                >
                  <Apple className="h-6 w-6" />
                  Download for iPhone
                  <ArrowRight className="h-5 w-5" />
                </Button>
                
                <Button
                  variant="outline"
                  className="border-gray-800 text-gray-400 hover:bg-gray-900 px-8 py-6 text-lg rounded-xl"
                  disabled
                >
                  Android Coming Soon
                </Button>
              </div>

              {/* QR Code Section - Desktop Only */}
              {!isMobile && (
                <div className="hidden lg:block">
                  <div className="inline-flex items-start gap-6 p-6 bg-gray-900/50 rounded-2xl border border-gray-800 backdrop-blur-xl">
                    <div className="text-left">
                      <p className="text-sm text-gray-500 mb-1">Scan to download</p>
                      <p className="text-lg font-medium">Point your iPhone camera here</p>
                    </div>
                    <div className="bg-white p-4 rounded-xl">
                      {/* QR Code pointing to App Store */}
                      <svg width="120" height="120" viewBox="0 0 120 120" className="text-black">
                        <rect width="120" height="120" fill="white"/>
                        {/* This is a placeholder - in production, use a real QR code generator */}
                        <path d="M10 10h20v20h-20zM40 10h10v10h-10zM60 10h10v10h-10zM80 10h10v10h-10zM90 10h20v20h-20zM10 40h10v10h-10zM30 40h20v10h-20zM60 40h10v10h-10zM80 40h10v10h-10zM100 40h10v10h-10zM10 60h10v10h-10zM30 60h10v10h-10zM50 60h20v10h-20zM80 60h10v10h-10zM100 60h10v10h-10zM10 80h10v10h-10zM30 80h20v10h-20zM60 80h10v10h-10zM80 80h10v10h-10zM100 80h10v10h-10zM10 90h20v20h-20zM40 100h10v10h-10zM60 100h10v10h-10zM80 100h10v10h-10zM90 90h20v20h-20z" fill="currentColor"/>
                      </svg>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Right - iPhone Mockup */}
            <div className="relative max-w-sm mx-auto lg:max-w-none">
              <div className="relative">
                {/* Glow effect */}
                <div className="absolute inset-0 bg-gradient-to-r from-blue-600/20 to-purple-600/20 blur-3xl"></div>
                
                {/* Phone */}
                <div className="relative mx-auto w-72 lg:w-80">
                  <div className="bg-gray-900 rounded-[3rem] p-2 shadow-2xl border border-gray-800">
                    <div className="bg-black rounded-[2.5rem] p-4">
                      {/* Screen Content */}
                      <div className="bg-gray-950 rounded-[2rem] p-6 h-[600px] relative overflow-hidden">
                        {/* Status Bar */}
                        <div className="flex justify-between items-center mb-6 text-xs">
                          <span className="text-gray-400 font-medium">9:41</span>
                          <div className="flex gap-1 items-center">
                            <div className="w-5 h-3 border border-gray-400 rounded-sm">
                              <div className="w-3 h-full bg-gray-400 rounded-sm"></div>
                            </div>
                          </div>
                        </div>

                        {/* App Content */}
                        <div className="space-y-4">
                          <h3 className="text-2xl font-bold">Today</h3>
                          
                          {/* FFMI Card */}
                          <div className="bg-gradient-to-br from-blue-600 to-purple-600 rounded-2xl p-4">
                            <div className="flex justify-between items-start mb-2">
                              <div>
                                <p className="text-blue-200 text-xs mb-1">Fat-Free Mass Index</p>
                                <p className="text-3xl font-bold">21.4</p>
                              </div>
                              <Badge className="bg-white/20 text-white border-0 text-xs">
                                Natural Peak
                              </Badge>
                            </div>
                            <div className="flex items-center gap-2 text-xs text-blue-200">
                              <TrendingUp className="h-3 w-3" />
                              <span>+0.3 this month • 87th percentile</span>
                            </div>
                          </div>

                          {/* Quick Stats */}
                          <div className="grid grid-cols-2 gap-3">
                            <div className="bg-gray-900 rounded-xl p-3">
                              <p className="text-gray-500 text-xs mb-1">Body Fat</p>
                              <p className="text-xl font-bold">12.3%</p>
                              <p className="text-xs text-green-400 flex items-center gap-1">
                                <span>↓</span> 0.5%
                              </p>
                            </div>
                            <div className="bg-gray-900 rounded-xl p-3">
                              <p className="text-gray-500 text-xs mb-1">Weight</p>
                              <p className="text-xl font-bold">180 lbs</p>
                              <p className="text-xs text-gray-400 flex items-center gap-1">
                                <span>→</span> stable
                              </p>
                            </div>
                          </div>

                          {/* Actions */}
                          <div className="space-y-2">
                            <button className="w-full bg-white text-black rounded-xl py-3 text-sm font-medium">
                              Log Measurement
                            </button>
                            <button className="w-full bg-gray-900 hover:bg-gray-800 text-white rounded-xl py-3 text-sm font-medium transition-colors">
                              Take Progress Photo
                            </button>
                          </div>

                          {/* Recent Activity */}
                          <div className="pt-4 border-t border-gray-800">
                            <p className="text-xs text-gray-500 mb-3">Recent activity</p>
                            <div className="space-y-3">
                              <div className="flex items-center justify-between">
                                <div className="flex items-center gap-3">
                                  <div className="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center">
                                    <Activity className="h-4 w-4 text-gray-400" />
                                  </div>
                                  <div>
                                    <p className="text-sm font-medium">Morning weight</p>
                                    <p className="text-xs text-gray-500">2 hours ago</p>
                                  </div>
                                </div>
                                <span className="text-sm text-gray-300">180.2</span>
                              </div>
                              <div className="flex items-center justify-between">
                                <div className="flex items-center gap-3">
                                  <div className="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center">
                                    <Camera className="h-4 w-4 text-gray-400" />
                                  </div>
                                  <div>
                                    <p className="text-sm font-medium">Progress photo</p>
                                    <p className="text-xs text-gray-500">Yesterday</p>
                                  </div>
                                </div>
                                <CheckCircle2 className="h-4 w-4 text-green-400" />
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                  
                  {/* Dynamic Island */}
                  <div className="absolute top-8 left-1/2 transform -translate-x-1/2 w-32 h-7 bg-black rounded-full"></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Stay on top Section - Linear Style */}
      <section className="py-20 border-t border-gray-900">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-4xl mx-auto">
            <div className="text-center mb-16">
              <h2 className="text-4xl sm:text-5xl font-bold mb-4">
                Stay on top of your most
                <br />
                important body metrics
              </h2>
              <p className="text-xl text-gray-400">
                Your pocket body composition lab. Always ready when you are.
              </p>
            </div>

            {/* Inbox Feature */}
            <div className="bg-gray-900/50 rounded-2xl p-8 border border-gray-800 mb-8">
              <div className="flex items-start gap-6">
                <div className="flex-shrink-0">
                  <div className="h-16 w-16 bg-blue-600/20 rounded-2xl flex items-center justify-center">
                    <Bell className="h-8 w-8 text-blue-500" />
                  </div>
                </div>
                <div className="flex-1">
                  <h3 className="text-2xl font-bold mb-3">Inbox</h3>
                  <p className="text-gray-400 text-lg mb-6">
                    Never miss a measurement. Smart reminders adapt to your schedule.
                  </p>
                  <div className="flex flex-wrap gap-3">
                    <Badge className="bg-gray-800 text-gray-300 border-gray-700 px-4 py-2">
                      <TouchpadOff className="h-3 w-3 mr-2 inline" />
                      Tap to log
                    </Badge>
                    <Badge className="bg-gray-800 text-gray-300 border-gray-700 px-4 py-2">
                      <Hand className="h-3 w-3 mr-2 inline" />
                      Swipe to dismiss
                    </Badge>
                    <Badge className="bg-gray-800 text-gray-300 border-gray-700 px-4 py-2">
                      <Timer className="h-3 w-3 mr-2 inline" />
                      Snooze for later
                    </Badge>
                  </div>
                </div>
              </div>
            </div>

            {/* Features Grid */}
            <div className="grid sm:grid-cols-2 gap-6">
              {features.map((feature, index) => {
                const IconComponent = feature.icon
                return (
                  <div
                    key={index}
                    className="group p-6 rounded-xl hover:bg-gray-900/50 transition-all border border-transparent hover:border-gray-800"
                  >
                    <div className="flex gap-4">
                      <div className="flex-shrink-0">
                        <div className="h-12 w-12 bg-gray-900 rounded-xl flex items-center justify-center group-hover:bg-gray-800 transition-colors">
                          <IconComponent className="h-6 w-6 text-gray-400" />
                        </div>
                      </div>
                      <div>
                        <h3 className="text-lg font-semibold mb-2">{feature.title}</h3>
                        <p className="text-gray-400 leading-relaxed">{feature.description}</p>
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Workflows Section */}
      <section className="py-20 border-t border-gray-900">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-4xl mx-auto">
            <div className="text-center mb-16">
              <Badge className="mb-4 bg-gray-900 text-gray-400 border-gray-800">
                Ultraportable
              </Badge>
              <h2 className="text-4xl sm:text-5xl font-bold mb-4">
                Designed for real life
              </h2>
              <p className="text-xl text-gray-400">
                From morning weigh-in to evening review
              </p>
            </div>

            <div className="space-y-4">
              {workflows.map((workflow, index) => {
                const IconComponent = workflow.icon
                return (
                  <div
                    key={index}
                    className="flex gap-6 p-6 bg-gray-900/30 rounded-2xl border border-gray-800 hover:border-gray-700 transition-all hover:bg-gray-900/50"
                  >
                    <div className="flex-shrink-0">
                      <div className="h-12 w-12 bg-gradient-to-br from-gray-800 to-gray-900 rounded-2xl flex items-center justify-center">
                        <IconComponent className="h-6 w-6 text-gray-300" />
                      </div>
                    </div>
                    <div className="flex-1">
                      <div className="flex items-start justify-between mb-2">
                        <h3 className="text-lg font-semibold">{workflow.title}</h3>
                        <span className="text-sm text-gray-500">{workflow.time}</span>
                      </div>
                      <p className="text-gray-400">{workflow.description}</p>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Tech Specs - Linear Style */}
      <section className="py-20 border-t border-gray-900">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-6xl mx-auto">
            <div className="text-center mb-16">
              <h2 className="text-4xl sm:text-5xl font-bold mb-4">
                Built different
              </h2>
              <p className="text-xl text-gray-400">
                Native performance. Privacy by design. AI at the edge.
              </p>
            </div>

            <div className="grid lg:grid-cols-3 gap-8">
              {techSpecs.map((spec, index) => {
                const IconComponent = spec.icon
                return (
                  <div key={index} className="text-center">
                    <div className="mb-6 inline-block">
                      <IconComponent className={cn("h-12 w-12", spec.color)} />
                    </div>
                    <h3 className="text-2xl font-bold mb-2">{spec.title}</h3>
                    <div className="text-3xl font-mono text-gray-400 mb-4">{spec.value}</div>
                    <p className="text-gray-400 leading-relaxed">
                      {spec.description}
                    </p>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      </section>

      {/* Availability Section */}
      <section className="py-20 border-t border-gray-900">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="max-w-4xl mx-auto text-center">
            <h2 className="text-4xl sm:text-5xl font-bold mb-4">
              Available 24/7.
              <br />
              <span className="text-gray-400">Or just 9-5.</span>
            </h2>
            <p className="text-xl text-gray-400 mb-12 max-w-2xl mx-auto">
              Configure notification schedules that respect your time. 
              Track on your terms, not ours.
            </p>

            <div className="bg-gray-900/50 rounded-2xl p-8 border border-gray-800 inline-block">
              <div className="grid grid-cols-7 gap-4 mb-6">
                {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) => (
                  <div key={day} className="text-center">
                    <p className="text-xs text-gray-500 mb-2">{day}</p>
                    <div className={cn(
                      "h-16 w-12 rounded-lg",
                      day === 'Sat' || day === 'Sun' 
                        ? "bg-gray-800" 
                        : "bg-gradient-to-b from-blue-600 to-purple-600"
                    )}></div>
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
      <section className="py-24 border-t border-gray-900">
        <div className="container mx-auto px-4 sm:px-6 text-center">
          <div className="max-w-3xl mx-auto">
            <h2 className="text-5xl sm:text-6xl lg:text-7xl font-bold mb-6">
              Your pocket
              <br />
              body comp lab
            </h2>
            <p className="text-xl text-gray-400 mb-10">
              Start tracking what matters. Available now on iPhone.
            </p>
            
            <div className="flex flex-col sm:flex-row gap-4 justify-center mb-12">
              <Button
                onClick={handleDownload}
                className="bg-white text-black px-10 py-6 text-lg font-medium rounded-xl hover:bg-gray-100 transition-all duration-200 shadow-2xl"
              >
                <Apple className="h-6 w-6 mr-3" />
                Download on App Store
              </Button>
              
              {!isMobile && (
                <Button
                  variant="outline"
                  onClick={() => setShowQR(!showQR)}
                  className="border-gray-800 text-gray-400 hover:bg-gray-900 px-10 py-6 text-lg rounded-xl"
                >
                  <QrCode className="h-6 w-6 mr-3" />
                  {showQR ? 'Hide' : 'Show'} QR Code
                </Button>
              )}
            </div>

            {/* QR Code Modal */}
            {showQR && !isMobile && (
              <div className="inline-block p-8 bg-gray-900 rounded-2xl border border-gray-800 mb-12">
                <p className="text-sm text-gray-500 mb-4">Scan with your iPhone camera</p>
                <div className="bg-white p-6 rounded-xl">
                  <svg width="200" height="200" viewBox="0 0 200 200" className="text-black">
                    <rect width="200" height="200" fill="white"/>
                    {/* Placeholder QR pattern */}
                    <path d="M20 20h40v40h-40zM140 20h40v40h-40zM20 140h40v40h-40zM80 20h20v20h-20zM100 40h20v20h-20zM80 60h20v20h-20zM100 80h20v20h-20zM80 100h20v20h-20zM100 120h20v20h-20zM80 140h20v20h-20zM140 80h20v20h-20zM160 100h20v20h-20zM140 120h20v20h-20z" fill="currentColor"/>
                  </svg>
                </div>
                <p className="text-xs text-gray-500 mt-4">Takes you straight to the App Store</p>
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
  )
}