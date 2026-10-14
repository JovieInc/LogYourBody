import type { Metadata } from 'next';
import Link from 'next/link';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';
import { logYourBody } from '@jovieinc/product-registry';

export const revalidate = false;

export const metadata: Metadata = { title: 'About', description: logYourBody.brand.description };
export default function AboutPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold text-balance sm:text-5xl">
          About {logYourBody.identity.name}
        </h1>
        <p className="text-secondary-token text-xl leading-8 text-pretty">
          {logYourBody.messages.landing.subheading}
        </p>
        <p className="text-secondary-token text-base leading-7">
          The iPhone app brings body measurements, supported Apple Health data, and progress photos
          into one timeline. The goal is to make changes easier to understand.
        </p>
      </section>
      <section className="max-w-prose-canonical border-subtle mt-16 space-y-5 border-t pt-12">
        <h2 className="text-2xl font-semibold">Keep the numbers in context</h2>
        <p className="text-secondary-token text-base leading-7">
          Body-composition measurements and estimates have limits. FFMI describes fat-free mass
          relative to height; it does not establish your genetic potential or diagnose health.
        </p>
        <Link
          href="/health-disclosure"
          className="focus-visible:outline-focus inline-flex min-h-11 items-center underline underline-offset-4 focus-visible:outline-2"
        >
          Read the health disclosure
        </Link>
      </section>
      <section className="max-w-prose-canonical border-subtle mt-16 space-y-5 border-t pt-12">
        <h2 className="text-2xl font-semibold">Your records, together</h2>
        <p className="text-secondary-token text-base leading-7">{logYourBody.brand.promise}</p>
        <Button asChild size="marketing" className="my-2">
          <Link href="/download/ios">Explore LogYourBody for iPhone</Link>
        </Button>
      </section>
    </MarketingPage>
  );
}
