'use client';

import './Footer.css';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { APP_CONFIG } from '@/constants/app';
import {
  MARKETING_FOOTER_COLUMNS,
  MARKETING_LEGAL_LINKS,
  type MarketingFooterLink,
} from '@/data/marketingNavigation';
import { LANDING_BRAND_ASSET } from '@/lib/marketing/landing-registry';
import { cn } from '@/lib/utils';
import { FOOTER_PEN_CONTRACT_ID, FOOTER_STATE_GALLERY_ID, resolveFooterVariant } from './config';
import type { FooterProps } from './types';

const markLinkClassName =
  '-m-1.5 inline-flex items-center rounded-full p-1.5 text-white/[0.92] transition-opacity hover:opacity-75 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/25';

function FooterLink({ link }: Readonly<{ link: MarketingFooterLink }>) {
  return (
    <Link
      href={link.href}
      prefetch={link.external ? undefined : false}
      className="mf-link"
      target={link.external ? '_blank' : undefined}
      rel={link.external ? 'noreferrer' : undefined}
    >
      {link.label}
    </Link>
  );
}

function BrandMark({ compact }: Readonly<{ compact?: boolean }>) {
  return (
    <Link href="/" prefetch={false} aria-label={`${APP_CONFIG.appName} home`} className={markLinkClassName}>
      <Image
        src={LANDING_BRAND_ASSET.src}
        alt=""
        width={22}
        height={22}
        className={cn('h-[22px] w-[22px]', compact ? 'rounded-md' : 'rounded-[5px]')}
      />
    </Link>
  );
}

function LegalNav({ className }: Readonly<{ className?: string }>) {
  return (
    <nav aria-label="Legal" className={cn('flex flex-wrap items-center gap-x-6 gap-y-2', className)}>
      {MARKETING_LEGAL_LINKS.map((link) => (
        <Link
          key={link.href}
          href={link.href}
          prefetch={false}
          className="mf-legal-link"
        >
          {link.label}
        </Link>
      ))}
    </nav>
  );
}

export function Footer({ variant = 'auto', className }: FooterProps) {
  const pathname = usePathname();
  const resolvedVariant = resolveFooterVariant(variant, pathname);
  const isCompact = resolvedVariant === 'compact';
  const copyright = `© ${new Date().getFullYear()} ${APP_CONFIG.companyName}`;

  return (
    <footer
      data-pen-contract={FOOTER_PEN_CONTRACT_ID}
      data-pen-gallery={FOOTER_STATE_GALLERY_ID}
      data-footer-mode={resolvedVariant}
      data-testid="marketing-footer"
      className={cn('marketing-footer-premium', className)}
      aria-label="Site footer"
    >
      <div
        className={cn(
          'mx-auto w-full max-w-7xl px-5 sm:px-8',
          isCompact
            ? 'pb-8 pt-6'
            : 'pb-[clamp(2.5rem,4vw,3.5rem)] pt-[clamp(4rem,6.5vw,6rem)]',
        )}
      >
        {isCompact ? null : (
          <div className="grid gap-12 md:grid-cols-[minmax(0,1fr)_minmax(0,2.6fr)] md:gap-x-16 lg:gap-x-24">
            <div className="min-w-0">
              <BrandMark />
            </div>

            <nav
              className="grid grid-cols-2 gap-x-8 gap-y-10 sm:grid-cols-3 lg:gap-x-12"
              aria-label="Footer"
            >
              {MARKETING_FOOTER_COLUMNS.map((column) => (
                <section key={column.title}>
                  <h2 className="mf-eyebrow">{column.title}</h2>
                  <ul className="flex list-none flex-col gap-3 p-0">
                    {column.links.map((link) => (
                      <li key={`${link.href}-${link.label}`}>
                        <FooterLink link={link} />
                      </li>
                    ))}
                  </ul>
                </section>
              ))}
            </nav>
          </div>
        )}

        <div
          className={cn(
            'mf-baseband flex flex-wrap items-center gap-x-7 gap-y-3',
            isCompact ? 'mf-baseband--compact justify-between' : 'justify-between',
          )}
        >
          {isCompact ? (
            <>
              <BrandMark compact />
              <div className="ml-auto flex flex-wrap items-center justify-end gap-x-6 gap-y-2">
                <LegalNav />
                <span className="mf-copyright">{copyright}</span>
              </div>
            </>
          ) : (
            <>
              <span className="mf-copyright">{copyright}</span>
              <LegalNav />
            </>
          )}
        </div>
      </div>
    </footer>
  );
}

export default Footer;
