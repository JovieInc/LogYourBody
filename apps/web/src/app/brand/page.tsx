import type { Metadata } from 'next';
import Image from 'next/image';
import { MarketingPage } from '@/components/MarketingPage';
import { Button } from '@jovie/ui/atoms/button';
import { logYourBody } from '@jovieinc/product-registry';
import { LANDING_BRAND_ASSET } from '@/lib/marketing/landing-registry';

export const revalidate = false;

export const metadata: Metadata = {
  alternates: { canonical: '/brand' },
  title: 'Brand',
  description: 'LogYourBody identity and brand assets.',
};
export default function BrandPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">LogYourBody brand</h1>
        <p className="text-secondary-token text-lg leading-8">{logYourBody.brand.promise}</p>
      </section>
      <section className="max-w-prose-canonical border-subtle mt-16 space-y-6 border-t pt-10">
        <h2 className="text-2xl font-semibold">App icon</h2>
        <Image src={LANDING_BRAND_ASSET.src} alt="LogYourBody app icon" width={96} height={96} />
        <p className="text-secondary-token text-base leading-7">
          Keep the artwork intact and preserve its proportions.
        </p>
        <Button asChild variant="link" className="text-primary-token">
          <a href={LANDING_BRAND_ASSET.src} download>
            Download the app icon
          </a>
        </Button>
      </section>
      <section className="max-w-prose-canonical border-subtle mt-16 space-y-6 border-t pt-10">
        <h2 className="text-2xl font-semibold">Typography and color</h2>
        <p className="text-secondary-token text-base leading-7">
          LogYourBody marketing uses the shared Jovie System B foundation: Inter for body and
          controls, Satoshi for display headings, and a dark neutral surface hierarchy. Accent
          colors communicate state or metric meaning.
        </p>
        <p className="text-secondary-token text-base leading-7">
          Write plainly. Distinguish measured values from estimates, and describe capabilities
          without promising health or appearance outcomes.
        </p>
      </section>
    </MarketingPage>
  );
}
