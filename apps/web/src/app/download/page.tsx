'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'

export default function DownloadPage() {
  const router = useRouter()

  useEffect(() => {
    // Detect user's platform and redirect accordingly
    const userAgent = navigator.userAgent || navigator.vendor
    const isIOS = /iPad|iPhone|iPod/.test(userAgent) && !('MSStream' in window)
    const isAndroid = /android/i.test(userAgent)

    if (isIOS) {
      router.push('/download/ios')
    } else if (isAndroid) {
      router.push('/download/android')
    } else {
      // Default to iOS for desktop users
      router.push('/download/ios')
    }
  }, [router])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-gray-900 mx-auto"></div>
        <p className="mt-4 text-gray-600">Detecting your device...</p>
      </div>
    </div>
  )
}
