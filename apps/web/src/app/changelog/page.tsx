import type { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { Button } from '@jovie/ui/atoms/button';
import { logYourBody } from '@jovieinc/product-registry';
export const revalidate = false;

export const metadata: Metadata = {
  title: 'Development history',
  description: 'View LogYourBody source changes on GitHub.',
};
export default function ChangelogPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">Development history</h1>
        <p className="text-secondary-token text-lg leading-8">
          Browse the source changes on GitHub. A source commit does not establish that a feature is
          available in the App Store release.
        </p>
        <Button asChild size="marketing" className="my-2">
          <a href={`${logYourBody.links.github}/commits/main`}>View source changes on GitHub</a>
        </Button>
      </section>
    </MarketingPage>
  );
}
