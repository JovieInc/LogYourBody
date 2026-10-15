import Image from 'next/image';
import Link from 'next/link';
import { LANDING_BRAND_ASSET } from '@/lib/marketing/landing-registry';
import { APP_CONFIG } from '@/constants/app';

export function MarketingBrand({ iconOnly = false }: { iconOnly?: boolean }) {
  return (
    <Link
      href="/"
      prefetch={false}
      aria-label={`${APP_CONFIG.appName} home`}
      className="text-primary-token focus-visible:outline-focus inline-flex min-h-11 min-w-11 items-center gap-3 rounded-md focus-visible:outline-2 focus-visible:outline-offset-4"
    >
      <Image
        src={LANDING_BRAND_ASSET.src}
        alt=""
        width={28}
        height={28}
        className="rounded-[7px]"
      />
      {iconOnly ? null : (
        <span className="text-[15px] font-medium tracking-[-0.01em]">{APP_CONFIG.appName}</span>
      )}
    </Link>
  );
}
