'use client';

import { useState, useEffect } from 'react';
import { Button } from '@shared-ui/atoms/button';
import { X, Share, Plus, Smartphone } from 'lucide-react';
import { cn } from '@/lib/utils';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export function PWAInstallPrompt() {
  const [showPrompt, setShowPrompt] = useState(false);
  const [isIOS, setIsIOS] = useState(false);
  const [isStandalone, setIsStandalone] = useState(false);
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    // Check if running on iOS
    const userAgent = window.navigator.userAgent.toLowerCase();
    const isIOSDevice = /iphone|ipad|ipod/.test(userAgent) && !('MSStream' in window);
    const isSafari =
      /safari/.test(userAgent) && !/chrome/.test(userAgent) && !/crios/.test(userAgent);

    // Check if already installed as PWA
    const isInStandaloneMode =
      window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: fullscreen)').matches ||
      window.matchMedia('(display-mode: minimal-ui)').matches ||
      window.matchMedia('(display-mode: window-controls-overlay)').matches ||
      ('standalone' in window.navigator && window.navigator.standalone === true) ||
      document.referrer.includes('android-app://') ||
      window.navigator.userAgent.includes('wv') ||
      // Additional checks for PWA on desktop
      window.location.href.includes('mode=standalone') ||
      window.location.search.includes('mode=standalone') ||
      // Check if launched from home screen on desktop
      window.matchMedia('(display-mode: browser)').matches === false;

    setIsIOS(isIOSDevice && isSafari);
    setIsStandalone(isInStandaloneMode);

    // Debug logging for PWA detection
    if (process.env.NODE_ENV === 'development') {
      console.log('PWA Detection:', {
        isInStandaloneMode,
        displayModeStandalone: window.matchMedia('(display-mode: standalone)').matches,
        displayModeBrowser: window.matchMedia('(display-mode: browser)').matches,
        navigatorStandalone:
          'standalone' in window.navigator ? window.navigator.standalone : 'not supported',
        userAgent: window.navigator.userAgent,
      });
    }

    // Don't show if already installed
    if (isInStandaloneMode) {
      return;
    }

    // Don't show if already installed or previously dismissed
    const dismissed = localStorage.getItem('pwa-install-dismissed');
    const lastDismissed = dismissed ? new Date(dismissed) : null;
    const daysSinceDismissed = lastDismissed
      ? (new Date().getTime() - lastDismissed.getTime()) / (1000 * 60 * 60 * 24)
      : Infinity;

    // Show prompt after 30 seconds if on iOS Safari and not installed
    // Re-show after 7 days if previously dismissed
    if (isIOSDevice && isSafari && !isInStandaloneMode && daysSinceDismissed > 7) {
      const timer = setTimeout(() => {
        setShowPrompt(true);
      }, 30000); // 30 seconds

      return () => clearTimeout(timer);
    }

    // Handle PWA install prompt for other browsers
    const handleBeforeInstallPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
      // Only show if not already installed and not recently dismissed
      if (!isInStandaloneMode && daysSinceDismissed > 7) {
        // Show custom install UI after 30 seconds
        setTimeout(() => {
          setShowPrompt(true);
        }, 30000);
      }
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    };
  }, []);

  const handleDismiss = () => {
    setShowPrompt(false);
    localStorage.setItem('pwa-install-dismissed', new Date().toISOString());
  };

  const handleInstall = async () => {
    if (deferredPrompt && !isIOS) {
      // Chrome/Edge/etc install flow
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;

      if (outcome === 'accepted') {
        console.log('PWA installed');
      }

      setDeferredPrompt(null);
      setShowPrompt(false);
    } else if (isIOS) {
      // Can't auto-trigger on iOS, just keep instructions visible
      // User must manually tap share and add to home screen
    }
  };

  if (!showPrompt || isStandalone) return null;

  return (
    <div
      className={cn(
        'safe-bottom animate-in slide-in-from-bottom-5 fixed right-0 bottom-0 left-0 z-50 p-4',
        'sm:right-auto sm:bottom-4 sm:left-4 sm:max-w-sm',
      )}
    >
      <div className="bg-linear-card border-linear-border rounded-2xl border p-4 shadow-2xl sm:p-6">
        <button
          onClick={handleDismiss}
          className="text-linear-text-tertiary hover:text-linear-text hover:bg-linear-border/50 absolute top-2 right-2 rounded-lg p-2 transition-colors"
          aria-label="Dismiss"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="pr-10">
          <div className="mb-4 flex items-start gap-4">
            <div className="bg-linear-purple/10 flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-xl">
              <Smartphone className="h-6 w-6 text-white" />
            </div>
            <div>
              <h3 className="text-linear-text mb-1 text-lg font-semibold">Install LogYourBody</h3>
              <p className="text-linear-text-secondary text-sm">
                Add to your home screen for the best experience
              </p>
            </div>
          </div>

          {isIOS ? (
            <>
              <div className="mb-4 space-y-3">
                <div className="flex items-center gap-3 text-sm">
                  <div className="bg-linear-purple/10 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg">
                    <Share className="h-4 w-4 text-white" />
                  </div>
                  <span className="text-linear-text">Tap the Share button below</span>
                </div>
                <div className="flex items-center gap-3 text-sm">
                  <div className="bg-linear-purple/10 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg">
                    <Plus className="h-4 w-4 text-white" />
                  </div>
                  <span className="text-linear-text">Select "Add to Home Screen"</span>
                </div>
                <div className="flex items-center gap-3 text-sm">
                  <div className="bg-linear-purple/10 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg">
                    <span className="text-xs font-semibold text-white">3</span>
                  </div>
                  <span className="text-linear-text">Tap "Add" to install</span>
                </div>
              </div>

              <div className="border-linear-border flex items-center gap-2 border-t pt-2">
                <Share className="text-linear-text-secondary h-4 w-4" />
                <p className="text-linear-text-secondary text-xs">
                  Find the Share button in your Safari toolbar
                </p>
              </div>
            </>
          ) : (
            <div className="flex gap-2">
              <Button
                onClick={handleInstall}
                className="bg-linear-purple hover:bg-linear-purple/80 flex-1"
              >
                Install App
              </Button>
              <Button
                onClick={handleDismiss}
                variant="ghost"
                className="text-linear-text-secondary"
              >
                Not Now
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
