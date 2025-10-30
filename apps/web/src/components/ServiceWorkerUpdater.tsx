'use client'

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { Button } from './ui/button'
import { RefreshCw } from 'lucide-react'
import { publicEnv } from '@/env'

export function ServiceWorkerUpdater() {
  const [showUpdateBar, setShowUpdateBar] = useState(false)
  const [waitingWorker, setWaitingWorker] = useState<ServiceWorker | null>(null)
  const pathname = usePathname()

  // Define external pages where update banner should not show
  const externalPages = [
    '/privacy',
    '/terms',
    '/health-disclosure',
    '/security',
    '/about',
    '/blog',
    '/support',
    '/contact',
    '/changelog',
    '/download'
  ]

  // Check if current page is an external page
  const isExternalPage = externalPages.some(page => pathname?.startsWith(page))

  useEffect(() => {
    // Only run in browser and not on external pages
    if (typeof window === 'undefined' || !('serviceWorker' in navigator) || isExternalPage) {
      return
    }

    // Check for service worker updates
    const checkForUpdates = async () => {
      try {
        const registration = await navigator.serviceWorker.getRegistration()
        if (registration) {
          // Check for updates immediately
          registration.update()

          // Listen for new service worker
          registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing
            if (newWorker) {
              newWorker.addEventListener('statechange', () => {
                if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                  // New service worker is ready
                  setWaitingWorker(newWorker)
                  setShowUpdateBar(true)
                }
              })
            }
          })
        }
      } catch (error) {
        console.error('Service worker update check failed:', error)
      }
    }

    checkForUpdates()

    // Check for updates every 30 seconds in development, every 5 minutes in production
    const interval = publicEnv.NODE_ENV === 'development' ? 30000 : 300000
    const updateInterval = setInterval(checkForUpdates, interval)

    // Also check when the page gains focus
    const handleFocus = () => checkForUpdates()
    window.addEventListener('focus', handleFocus)

    return () => {
      clearInterval(updateInterval)
      window.removeEventListener('focus', handleFocus)
    }
  }, [isExternalPage])

  const handleUpdate = () => {
    if (waitingWorker) {
      // Tell the service worker to skip waiting
      waitingWorker.postMessage({ type: 'SKIP_WAITING' })

      // Reload once the new service worker takes control
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        window.location.reload()
      })
    }
  }

  // Don't show on external pages
  if (!showUpdateBar || isExternalPage) return null

  return (
    <div className="fixed bottom-0 left-0 right-0 z-50 p-4 bg-linear-card border-t border-linear-border shadow-lg animate-in slide-in-from-bottom-5">
      <div className="container mx-auto flex items-center justify-between">
        <div className="flex items-center gap-3">
          <RefreshCw className="h-5 w-5 text-linear-purple animate-spin" />
          <div>
            <p className="text-sm font-medium text-linear-text">Update available!</p>
            <p className="text-xs text-linear-text-secondary">
              A new version of LogYourBody is ready to install.
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowUpdateBar(false)}
          >
            Later
          </Button>
          <Button
            size="sm"
            onClick={handleUpdate}
            className="bg-linear-purple hover:bg-linear-purple/90"
          >
            Update Now
          </Button>
        </div>
      </div>
    </div>
  )
}