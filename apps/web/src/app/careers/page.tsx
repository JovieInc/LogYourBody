import type { Metadata } from 'next';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';
import { logYourBody } from '@jovieinc/product-registry';

export const revalidate = false;

export const metadata: Metadata = {
  title: 'Careers',
  description: 'Contact LogYourBody about working together.',
};
export default function CareersPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">Work with LogYourBody</h1>
        <p className="text-secondary-token text-lg leading-8">
          For questions about opportunities, contact us directly. We do not list confirmed openings
          or employment benefits on this page.
        </p>
        <Button asChild size="marketing" className="my-2">
          <a href={`mailto:${logYourBody.contacts.careers}`}>Contact us about careers</a>
        </Button>
      </section>
    </MarketingPage>
  );
}
