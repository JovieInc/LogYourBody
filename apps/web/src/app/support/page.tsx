import type { Metadata } from 'next';
import Link from 'next/link';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';
import { getPublicSupportOptions, logYourBody } from '@jovieinc/product-registry';

export const revalidate = false;

export const metadata: Metadata = {
  title: 'Support',
  description: `Get help with ${logYourBody.identity.name}, your account, subscription, or data.`,
};
export default function SupportPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">How can we help?</h1>
        <p className="text-secondary-token text-lg leading-8">
          Get help with LogYourBody, your account, subscription, or data.
        </p>
      </section>
      <section
        aria-label="Support options"
        className="border-subtle mt-12 grid gap-10 border-t pt-10 sm:grid-cols-2"
      >
        {getPublicSupportOptions().map((option) => (
          <div key={option.id} className="max-w-[40ch] space-y-4">
            <h2 className="text-xl font-semibold">{option.label}</h2>
            <p className="text-secondary-token text-base leading-7">{option.description}</p>
            <Button asChild variant="link" className="text-primary-token">
              <a href={option.href}>
                {option.kind === 'email' ? logYourBody.contacts.support : option.label}
              </a>
            </Button>
          </div>
        ))}
      </section>
      <section className="max-w-prose-canonical border-subtle mt-16 space-y-8 border-t pt-10">
        <h2 className="text-2xl font-semibold">Common questions</h2>
        <div className="space-y-3">
          <h3 className="text-lg font-medium">How do I export my data?</h3>
          <p className="text-secondary-token text-base leading-7">
            Use the export option in the iPhone app settings. If you cannot access the app, contact{' '}
            <a
              className="underline underline-offset-4"
              href={`mailto:${logYourBody.contacts.support}`}
            >
              {logYourBody.contacts.support}
            </a>{' '}
            to request a copy.
          </p>
        </div>
        <div className="space-y-3">
          <h3 className="text-lg font-medium">How is my data used?</h3>
          <p className="text-secondary-token text-base leading-7">
            Your timeline is private. Service providers help operate the app, storage,
            authentication, and subscriptions. Read the{' '}
            <Link className="underline underline-offset-4" href="/privacy">
              privacy policy
            </Link>{' '}
            for details about collection, sharing, retention, and your choices.
          </p>
        </div>
        <div className="space-y-3">
          <h3 className="text-lg font-medium">How do I manage my subscription?</h3>
          <p className="text-secondary-token text-base leading-7">
            Manage App Store subscriptions through your Apple account settings. The App Store shows
            the terms that apply to your purchase.
          </p>
        </div>
        <nav aria-label="Support resources" className="flex flex-wrap gap-6">
          {[
            ['/privacy', 'Privacy policy'],
            ['/terms', 'Terms of service'],
            ['/download', 'Explore iPhone'],
            ['/delete-account', 'Delete account'],
            ['/security', 'Report a security issue'],
          ].map(([href, label]) => (
            <Link
              key={href}
              className="focus-visible:outline-focus inline-flex min-h-11 items-center underline underline-offset-4 focus-visible:outline-2"
              href={href}
            >
              {label}
            </Link>
          ))}
        </nav>
      </section>
    </MarketingPage>
  );
}
