'use client'

import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ArrowLeft, Smartphone } from 'lucide-react'
import { Header } from '@/components/Header'
import { Footer } from '@/components/Footer'

export default function AndroidDownloadPage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-gray-50 to-white">
      <Header />

      <section className="py-24">
        <div className="container mx-auto px-4 sm:px-6">
          <div className="mx-auto max-w-2xl text-center">
            <Badge className="mb-8 bg-green-50 text-green-700 border-green-200 inline-flex">
              <Smartphone className="h-4 w-4 mr-2" />
              Coming Soon to Android
            </Badge>

            <h1 className="mb-6 text-4xl sm:text-5xl font-bold text-gray-900">
              Android app in development
            </h1>

            <p className="mb-10 text-xl text-gray-600 leading-relaxed">
              We&apos;re working hard to bring LogYourBody to Android. 
              Join the waitlist to be notified when it&apos;s ready.
            </p>

            <div className="space-y-4">
              <Button
                className="bg-green-600 text-white px-8 py-4 text-lg rounded-xl hover:bg-green-700 transition-all"
                onClick={() => window.open('https://forms.gle/android-waitlist', '_blank')}
              >
                Join Android Waitlist
              </Button>

              <div className="mt-8">
                <Link href="/download/ios">
                  <Button variant="outline" className="group">
                    <ArrowLeft className="h-4 w-4 mr-2 group-hover:-translate-x-1 transition-transform" />
                    Available now on iOS
                  </Button>
                </Link>
              </div>
            </div>

            <p className="mt-12 text-sm text-gray-500">
              In the meantime, you can use our web app on any device
            </p>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  )
}