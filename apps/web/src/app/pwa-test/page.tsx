'use client'

import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import type { BeforeInstallPromptEvent } from '@/types/pwa'

export default function PWATestPage() {
  const [swStatus, setSwStatus] = useState<string>('Checking...')
  const [isInstallable, setIsInstallable] = useState(false)
  const [isStandalone, setIsStandalone] = useState(false)
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null)

  useEffect(() => {
    // Check if running in standalone mode
    const standalone = window.matchMedia('(display-mode: standalone)').matches
    setIsStandalone(standalone)

    // Check service worker status
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistration().then((registration) => {
        if (registration) {
          if (registration.active) {
            setSwStatus('Active ✓')
          } else if (registration.installing) {
            setSwStatus('Installing...')
          } else if (registration.waiting) {
            setSwStatus('Waiting...')
          } else {
            setSwStatus('Registered')
          }
        } else {
          setSwStatus('Not registered')
        }
      })
    } else {
      setSwStatus('Not supported')
    }

    // Listen for install prompt
    const handleBeforeInstallPrompt = (e: Event) => {
      const promptEvent = e as BeforeInstallPromptEvent
      promptEvent.preventDefault()
      setDeferredPrompt(promptEvent)
      setIsInstallable(true)
    }

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt as EventListener)

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt as EventListener)
    }
  }, [])

  const handleInstall = async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt()
      const { outcome } = await deferredPrompt.userChoice
      console.log(`User response to install prompt: ${outcome}`)
      setDeferredPrompt(null)
      setIsInstallable(false)
    }
  }

  const handleTestNotification = async () => {
    if ('Notification' in window) {
      const permission = await Notification.requestPermission()
      if (permission === 'granted') {
        new Notification('LogYourBody', {
          body: 'Notifications are working!',
          icon: '/android-chrome-192x192.png',
          badge: '/android-chrome-192x192.png'
        })
      }
    }
  }

  return (
    <div className="container mx-auto p-4 max-w-2xl">
      <h1 className="text-3xl font-bold mb-6">PWA Test Page</h1>

      <div className="space-y-4">
        <Card className="p-4">
          <h2 className="text-xl font-semibold mb-2">PWA Status</h2>
          <div className="space-y-2">
            <p>Service Worker: <span className="font-mono">{swStatus}</span></p>
            <p>Display Mode: <span className="font-mono">{isStandalone ? 'Standalone' : 'Browser'}</span></p>
            <p>Installable: <span className="font-mono">{isInstallable ? 'Yes' : 'No'}</span></p>
          </div>
        </Card>

        <Card className="p-4">
          <h2 className="text-xl font-semibold mb-2">PWA Features</h2>
          <div className="space-y-2">
            <Button
              onClick={handleInstall}
              disabled={!isInstallable}
              className="w-full"
            >
              Install App
            </Button>

            <Button
              onClick={handleTestNotification}
              variant="outline"
              className="w-full"
            >
              Test Notification
            </Button>

            <Button
              onClick={() => navigator.serviceWorker.getRegistration().then(r => r?.update())}
              variant="outline"
              className="w-full"
            >
              Check for Updates
            </Button>
          </div>
        </Card>

        <Card className="p-4">
          <h2 className="text-xl font-semibold mb-2">PWA Checklist</h2>
          <ul className="space-y-1">
            <li>✓ Service Worker registered</li>
            <li>✓ Web App Manifest configured</li>
            <li>✓ HTTPS enabled (required for production)</li>
            <li>✓ Offline page ready</li>
            <li>✓ App icons configured</li>
            <li>✓ Install prompt handling</li>
            <li>✓ Update notifications</li>
          </ul>
        </Card>

        <Card className="p-4">
          <h2 className="text-xl font-semibold mb-2">Test Offline Mode</h2>
          <p className="text-sm text-muted-foreground mb-2">
            To test offline functionality:
          </p>
          <ol className="list-decimal list-inside space-y-1 text-sm">
            <li>Open DevTools (F12)</li>
            <li>Go to Network tab</li>
            <li>Enable "Offline" mode</li>
            <li>Navigate to different pages</li>
            <li>You should see the offline page for uncached routes</li>
          </ol>
        </Card>
      </div>
    </div>
  )
}
