import { COMPACT_FOOTER_PATHS } from '@/data/marketingNavigation';
import type { FooterVariant, ResolvedFooterVariant } from './types';

export const FOOTER_PEN_CONTRACT_ID = 'CCDnQ';
export const FOOTER_STATE_GALLERY_ID = 'T32Pu';

export function normalizeFooterPath(pathname: string | null | undefined): string {
  if (!pathname) {
    return '/';
  }

  if (pathname.length > 1 && pathname.endsWith('/')) {
    return pathname.slice(0, -1);
  }

  return pathname;
}

export function resolveFooterVariant(
  variant: FooterVariant,
  pathname: string | null | undefined,
): ResolvedFooterVariant {
  if (variant === 'full' || variant === 'compact') {
    return variant;
  }

  return COMPACT_FOOTER_PATHS.has(normalizeFooterPath(pathname)) ? 'compact' : 'full';
}
