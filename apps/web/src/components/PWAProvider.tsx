'use client'

import { useEffect } from 'react'
import { toast } from '@/hooks/use-toast'
import type { BeforeInstallPromptEvent } from '@/types/pwa'

export function PWAProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    if (typeof window !== 'undefined' && 'serviceWorker' in navigator) {
      // Register service worker
      window.addEventListener('load', () => {
        navigator.serviceWorker
          .register('/sw.js')
          .then((registration) => {
            console.log('SW registered: ', registration)
            
            // Handle updates
            registration.addEventListener('updatefound', () => {
              const newWorker = registration.installing
              if (newWorker) {
                newWorker.addEventListener('statechange', () => {
                  if (newWorker.state === 'activated') {
                    toast({
                      title: 'App Updated',
                      description: 'New version available. Refresh to update.',
                      action: (
                        <button
                          onClick={() => window.location.reload()}
                          className="text-sm font-medium"
                        >
                          Refresh
                        </button>
                      ),
                    })
                  }
                })
              }
            })
          })
          .catch((registrationError) => {
            console.log('SW registration failed: ', registrationError)
          })
      })

      // Listen for app install prompt
      let deferredPrompt: BeforeInstallPromptEvent | null = null
      window.addEventListener('beforeinstallprompt', (e) => {
        e.preventDefault()
        deferredPrompt = e
        
        // Show install button after 30 seconds
        setTimeout(() => {
          if (deferredPrompt) {
            toast({
              title: 'Install LogYourBody',
              description: 'Add to your home screen for the best experience',
              action: (
                <button
                  onClick={async () => {
                    if (deferredPrompt) {
                      deferredPrompt.prompt()
                      const { outcome } = await deferredPrompt.userChoice
                      console.log(`User response to install prompt: ${outcome}`)
                      deferredPrompt = null
                    }
                  }}
                  className="text-sm font-medium"
                >
                  Install
                </button>
              ),
              duration: 10000,
            })
          }
        }, 30000)
      })

      // Handle app installed
      window.addEventListener('appinstalled', () => {
        console.log('PWA was installed')
        toast({
          title: 'App Installed!',
          description: 'LogYourBody has been added to your home screen',
        })
      })
    }
  }, [])

  return <>{children}</>
}
