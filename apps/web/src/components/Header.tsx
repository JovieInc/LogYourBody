'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { FeaturesFlyout } from './FeaturesFlyout';
import { Menu, X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { logYourBody } from '@jovieinc/product-registry';

interface HeaderProps {
  onFeatureClick?: (featureId: string) => void;
  showFeatures?: boolean;
}

export function Header({ onFeatureClick, showFeatures = false }: HeaderProps) {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const pathname = usePathname();

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
      setMobileMenuOpen(false);
    }
  };

  const handleFeatureClick = (featureId: string) => {
    if (onFeatureClick) {
      onFeatureClick(featureId);
    } else {
      scrollToSection(featureId);
    }
    setMobileMenuOpen(false);
  };

  const isActive = (path: string) => pathname === path;

  return (
    <header className="sticky top-0 z-50 w-full border-b border-white/[0.08] bg-black/40 backdrop-blur-xl backdrop-saturate-150 supports-[backdrop-filter]:bg-black/60">
      <div className="mx-auto max-w-7xl">
        <nav className="flex h-16 items-center justify-between px-6 lg:px-8" aria-label="Global">
          <div className="flex items-center gap-x-12">
            <Link href="/" className="flex items-center">
              <span className="text-base font-semibold text-white">
                {logYourBody.identity.name}
              </span>
            </Link>
            {/* Desktop navigation */}
            <div className="hidden lg:flex lg:gap-x-8">
              {showFeatures && <FeaturesFlyout onFeatureClick={handleFeatureClick} />}
              {showFeatures && (
                <button
                  className="text-sm font-medium text-white/60 transition-colors hover:text-white"
                  onClick={() => scrollToSection('pricing')}
                >
                  Pricing
                </button>
              )}
              <Link
                href="/about"
                className={cn(
                  'text-sm font-medium transition-colors',
                  isActive('/about') ? 'text-white' : 'text-white/60 hover:text-white',
                )}
              >
                About
              </Link>
              <Link
                href="/blog"
                className={cn(
                  'text-sm font-medium transition-colors',
                  isActive('/blog') ? 'text-white' : 'text-white/60 hover:text-white',
                )}
              >
                Blog
              </Link>
              <Link
                href="/download/ios"
                className={cn(
                  'text-sm font-medium transition-colors',
                  isActive('/download/ios') ? 'text-white' : 'text-white/60 hover:text-white',
                )}
              >
                iOS
              </Link>
            </div>
          </div>

          {/* Mobile menu button */}
          <div className="flex lg:hidden">
            <button
              type="button"
              className="-m-2.5 inline-flex items-center justify-center rounded-md p-2.5 text-white/60 hover:text-white"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            >
              <span className="sr-only">Open main menu</span>
              {mobileMenuOpen ? (
                <X className="h-5 w-5" aria-hidden="true" />
              ) : (
                <Menu className="h-5 w-5" aria-hidden="true" />
              )}
            </button>
          </div>

          {/* Desktop CTA buttons */}
          <div className="hidden lg:flex lg:items-center lg:gap-x-4">
            <Link
              href="/download/ios"
              className="rounded-full bg-white px-4 py-2 text-sm font-medium text-black transition-all hover:bg-white/90"
            >
              Download App
            </Link>
          </div>
        </nav>
      </div>

      {/* Mobile menu */}
      <div className={cn('lg:hidden', mobileMenuOpen ? 'block' : 'hidden')}>
        <div className="mx-auto max-w-7xl">
          <div className="space-y-1 px-6 pb-3 pt-2">
            {showFeatures && (
              <button
                className="block px-3 py-2 text-base font-medium text-white/60 transition-colors hover:text-white"
                onClick={() => scrollToSection('features')}
              >
                Features
              </button>
            )}
            {showFeatures && (
              <button
                className="block px-3 py-2 text-base font-medium text-white/60 transition-colors hover:text-white"
                onClick={() => scrollToSection('pricing')}
              >
                Pricing
              </button>
            )}
            <Link
              href="/about"
              className={cn(
                'block px-3 py-2 text-base font-medium transition-colors',
                isActive('/about') ? 'text-white' : 'text-white/60 hover:text-white',
              )}
              onClick={() => setMobileMenuOpen(false)}
            >
              About
            </Link>
            <Link
              href="/blog"
              className={cn(
                'block px-3 py-2 text-base font-medium transition-colors',
                isActive('/blog') ? 'text-white' : 'text-white/60 hover:text-white',
              )}
              onClick={() => setMobileMenuOpen(false)}
            >
              Blog
            </Link>
            <Link
              href="/download/ios"
              className={cn(
                'block px-3 py-2 text-base font-medium transition-colors',
                isActive('/download/ios') ? 'text-white' : 'text-white/60 hover:text-white',
              )}
              onClick={() => setMobileMenuOpen(false)}
            >
              iOS
            </Link>
            <div className="mt-6 space-y-2">
              <Link
                href="/download/ios"
                className="block rounded-full bg-white px-3 py-2 text-center text-base font-medium text-black transition-all hover:bg-gray-100"
                onClick={() => setMobileMenuOpen(false)}
              >
                Download App
              </Link>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}
