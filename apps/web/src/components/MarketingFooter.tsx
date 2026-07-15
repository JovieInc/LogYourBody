import Image from 'next/image';
import Link from 'next/link';
import { APP_CONFIG } from '@/constants/app';
import { LANDING_BRAND_ASSET } from '@/lib/marketing/landing-registry';

const legalLinks = [
  { href: '/privacy', label: 'Privacy' },
  { href: '/terms', label: 'Terms' },
  { href: '/health-disclosure', label: 'Health disclosure' },
  { href: '/support', label: 'Support' },
] as const;

/**
 * LogYourBody adaptation of Jovie's canonical minimal marketing footer.
 * Keep the structure and surface treatment aligned across both products.
 */
export function MarketingFooter() {
  return (
    <footer
      className="border-t border-white/[0.07] bg-[#06070a] text-white"
      data-testid="marketing-footer"
    >
      <div className="mx-auto w-full max-w-7xl px-5 pb-10 pt-12 sm:px-8 sm:pb-12 sm:pt-16">
        <Link
          href="/"
          aria-label="LogYourBody home"
          className="-m-1.5 inline-flex items-center gap-2 rounded-full p-1.5 text-white/[0.92] transition-opacity hover:opacity-75 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/25"
        >
          <Image
            src={LANDING_BRAND_ASSET.src}
            alt=""
            width={LANDING_BRAND_ASSET.width}
            height={LANDING_BRAND_ASSET.height}
            className="h-[22px] w-[22px] rounded-md"
          />
          <span className="text-sm font-medium tracking-[-0.02em]">{APP_CONFIG.appName}</span>
        </Link>

        <div className="mt-7 flex flex-col gap-4 border-t border-white/[0.07] pt-6 sm:flex-row sm:items-center sm:justify-between">
          <span className="text-xs leading-5 tracking-[-0.005em] text-white/50">
            © {new Date().getFullYear()} {APP_CONFIG.companyName} All rights reserved.
          </span>
          <nav aria-label="Legal" className="flex flex-wrap items-center gap-x-6 gap-y-2">
            {legalLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                prefetch={false}
                className="rounded text-xs leading-5 tracking-tight text-white/50 transition-colors hover:text-white/75 focus-visible:text-white/75 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/25"
              >
                {link.label}
              </Link>
            ))}
          </nav>
        </div>
      </div>
    </footer>
  );
}
