'use client';

import { useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Button } from '@jovie/ui/atoms/button';
import { Menu, X } from 'lucide-react';
import { MarketingBrand } from './MarketingBrand';
import { LANDING_FLAGS } from '@/lib/flags/landing';

interface HeaderProps {
  onFeatureClick?: (featureId: string) => void;
  showFeatures?: boolean;
}

const links = [
  { href: '/about', label: 'About' },
  { href: '/blog', label: 'Blog' },
  { href: '/download/ios', label: 'iOS' },
];

export function Header({ showFeatures = false, onFeatureClick }: HeaderProps) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const pathname = usePathname();
  const action = LANDING_FLAGS.APP_STORE_LIVE ? 'Download for iOS' : 'Request early access';
  function close() {
    setOpen(false);
    trigger.current?.focus();
  }
  return (
    <header
      className="lyb-marketing border-subtle sticky top-0 z-40 border-b"
      onKeyDown={(event) => {
        if (event.key === 'Escape' && open) close();
      }}
    >
      <nav
        className="max-w-public-content mx-auto flex h-20 items-center justify-between gap-6 px-5 sm:px-8"
        aria-label="Global"
      >
        <MarketingBrand />
        <div className="hidden items-center gap-8 lg:flex">
          {showFeatures && (
            <Button variant="ghost" onClick={() => onFeatureClick?.('features')}>
              Features
            </Button>
          )}
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              aria-current={pathname === link.href ? 'page' : undefined}
              className="text-secondary-token hover:text-primary-token focus-visible:outline-focus inline-flex min-h-11 items-center text-sm focus-visible:outline-2 focus-visible:outline-offset-4"
            >
              {link.label}
            </Link>
          ))}
          <Button asChild size="marketing">
            <Link href="/download/ios">{action}</Link>
          </Button>
        </div>
        <Button
          ref={trigger}
          variant="ghost"
          size="icon"
          className="lg:hidden"
          aria-label={open ? 'Close main menu' : 'Open main menu'}
          aria-expanded={open}
          aria-controls="marketing-navigation"
          onClick={() => setOpen(!open)}
        >
          {open ? (
            <X aria-hidden="true" className="h-5 w-5" />
          ) : (
            <Menu aria-hidden="true" className="h-5 w-5" />
          )}
        </Button>
      </nav>
      {open && (
        <nav
          id="marketing-navigation"
          aria-label="Mobile"
          className="max-w-public-content mx-auto grid gap-4 px-5 pb-6 lg:hidden"
        >
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              aria-current={pathname === link.href ? 'page' : undefined}
              onClick={() => setOpen(false)}
              className="text-secondary-token focus-visible:outline-focus inline-flex min-h-11 items-center text-base focus-visible:outline-2 focus-visible:outline-offset-4"
            >
              {link.label}
            </Link>
          ))}
          <Button asChild size="marketing" className="my-2 w-fit">
            <Link href="/download/ios" onClick={() => setOpen(false)}>
              {action}
            </Link>
          </Button>
        </nav>
      )}
    </header>
  );
}
