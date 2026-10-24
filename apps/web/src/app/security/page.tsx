import type { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { Button } from '@jovie/ui/atoms/button';
import { logYourBody } from '@jovieinc/product-registry';
export const revalidate = false;

export const metadata: Metadata = {
  title: 'Security',
  description: 'Report a security vulnerability in LogYourBody privately.',
  alternates: { canonical: '/security' },
};

export default function SecurityPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">Report a security issue</h1>
        <p className="text-secondary-token text-lg leading-8">
          If you found a vulnerability in LogYourBody, report it privately through GitHub. Do not
          post vulnerability details in a public issue.
        </p>
        <p className="text-secondary-token text-base leading-7">
          You will need to sign in to GitHub to write and submit your report. Opening the link below
          does not submit a report.
        </p>
        <Button asChild size="marketing" className="my-2">
          <a href={`${logYourBody.links.github}/security/advisories/new`}>
            Report privately on GitHub
          </a>
        </Button>
        <h2 className="pt-8 text-2xl font-semibold">What to include</h2>
        <ul className="text-secondary-token list-disc space-y-3 pl-5 text-base leading-7">
          <li>The affected feature, app version, or page.</li>
          <li>Steps to reproduce the issue and its potential impact.</li>
          <li>A safe example with personal data and secrets removed.</li>
        </ul>
        <p className="text-secondary-token text-base leading-7">
          Avoid accessing other people&apos;s data or performing destructive tests.
        </p>
      </section>
    </MarketingPage>
  );
}
