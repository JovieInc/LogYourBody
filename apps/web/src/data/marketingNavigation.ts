import { logYourBody } from '@jovieinc/product-registry';

export interface MarketingNavLink {
  readonly href: string;
  readonly label: string;
}

export interface MarketingFooterLink extends MarketingNavLink {
  readonly external?: boolean;
}

export interface MarketingFooterColumn {
  readonly title: string;
  readonly links: readonly MarketingFooterLink[];
}

export const MARKETING_FOOTER_COLUMNS: readonly MarketingFooterColumn[] = [
  {
    title: 'Product',
    links: [
      { href: '/download', label: 'Download' },
      { href: '/changelog', label: 'Changelog' },
      { href: '/blog', label: 'Blog' },
    ],
  },
  {
    title: 'Company',
    links: [
      { href: '/about', label: 'About' },
      { href: '/careers', label: 'Careers' },
      { href: '/brand', label: 'Brand' },
    ],
  },
  {
    title: 'Resources',
    links: [
      { href: '/support', label: 'Support' },
      { href: '/security', label: 'Security' },
      { href: logYourBody.links.status, label: 'Status', external: true },
    ],
  },
] as const;

export const MARKETING_LEGAL_LINKS: readonly MarketingFooterLink[] = [
  { href: '/privacy', label: 'Privacy' },
  { href: '/terms', label: 'Terms' },
  { href: '/health-disclosure', label: 'Health disclosure' },
] as const;

export const COMPACT_FOOTER_PATHS = new Set<string>([
  '/privacy',
  '/terms',
  '/health-disclosure',
  '/security',
]);
