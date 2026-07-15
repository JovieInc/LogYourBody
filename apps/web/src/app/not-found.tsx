'use client';

import Link from 'next/link';
import { useAuth } from '@/contexts/ProductAuthContext';
import { Button } from '@/components/ui/button';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { Search, Home, ArrowLeft, Settings } from 'lucide-react';

export default function NotFound() {
  const { user } = useAuth();

  return (
    <div className="bg-linear-bg font-inter min-h-screen">
      <Header />

      <div className="flex flex-1 items-center justify-center px-4 py-16">
        <div className="max-w-md text-center">
          <div className="mb-8">
            <div className="bg-linear-purple/10 mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full">
              <Search className="text-linear-purple h-10 w-10" />
            </div>
            <h1 className="text-linear-text mb-2 text-4xl font-bold">Page Not Found</h1>
            <p className="text-linear-text-secondary text-lg">
              Sorry, we couldn&apos;t find the page you&apos;re looking for.
            </p>
          </div>

          <div className="space-y-4">
            <div className="flex flex-col justify-center gap-3 sm:flex-row">
              {user ? (
                <>
                  <Link href="/dashboard">
                    <Button className="bg-linear-text text-linear-bg hover:bg-linear-text/90 inline-flex items-center gap-2 px-6 py-3">
                      <Home className="h-4 w-4" />
                      Go to Dashboard
                    </Button>
                  </Link>

                  <Link href="/settings">
                    <Button
                      variant="ghost"
                      className="text-linear-text-secondary hover:text-linear-text border-linear-border hover:bg-linear-border/50 inline-flex items-center gap-2 border px-6 py-3"
                    >
                      <Settings className="h-4 w-4" />
                      Settings
                    </Button>
                  </Link>
                </>
              ) : (
                <>
                  <Link href="/">
                    <Button className="bg-linear-text text-linear-bg hover:bg-linear-text/90 inline-flex items-center gap-2 px-6 py-3">
                      <Home className="h-4 w-4" />
                      Go Home
                    </Button>
                  </Link>

                  <Link href="/download/ios">
                    <Button
                      variant="ghost"
                      className="text-linear-text-secondary hover:text-linear-text border-linear-border hover:bg-linear-border/50 border px-6 py-3"
                    >
                      Download App
                    </Button>
                  </Link>
                </>
              )}
            </div>

            <Button
              variant="ghost"
              onClick={() => window.history.back()}
              className="text-linear-text-secondary hover:text-linear-text inline-flex items-center gap-2 px-6 py-3"
            >
              <ArrowLeft className="h-4 w-4" />
              Go Back
            </Button>

            <div className="text-linear-text-tertiary mt-8 text-sm">
              <p>
                If you think this is a mistake, please{' '}
                <Link href="/about" className="text-linear-purple hover:underline">
                  contact support
                </Link>
                .
              </p>
            </div>
          </div>
        </div>
      </div>

      <Footer />
    </div>
  );
}
