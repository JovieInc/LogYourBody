import { Metadata } from 'next';
import Link from 'next/link';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';
import { logYourBody } from '@jovieinc/product-registry';

const deletionRequestHref =
  `mailto:${logYourBody.contacts.support}` +
  '?subject=' +
  encodeURIComponent('LogYourBody Account Deletion Request') +
  '&body=' +
  encodeURIComponent(
    'Hello LogYourBody Support,\n\n' +
      'I would like to permanently delete my LogYourBody account and associated data.\n\n' +
      'The email address on my account is:\n\n' +
      'Thank you,',
  );

export const metadata: Metadata = {
  title: 'Delete Account - LogYourBody',
  description: 'How to permanently delete your LogYourBody account and request help from support.',
};

export const revalidate = false;
export default function DeleteAccountPage() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">
          Delete your LogYourBody account
        </h1>
        <p className="text-secondary-token text-lg leading-8">
          You can permanently delete your account from the iOS app. If you no longer have access to
          the app, support can help process the request by email.
        </p>
        <ol className="text-secondary-token list-decimal space-y-4 pl-6 text-base leading-7">
          <li>In the iOS app, go to Settings, then Account.</li>
          <li>Choose Delete Account and follow the confirmation prompts.</li>
          <li>
            If you need help, contact support with the email address associated with your account.
          </li>
        </ol>
        <p className="text-secondary-token text-base leading-7">
          Account deletion is permanent. Deleting your account does not cancel an App Store
          subscription; manage subscriptions through your Apple account settings.
        </p>
        <div className="flex flex-wrap gap-6 py-2">
          <Button asChild size="marketing">
            <Link href="/download/ios">Explore iPhone early access</Link>
          </Button>
          <Button asChild variant="secondary" size="marketing">
            <a href={deletionRequestHref}>Email support</a>
          </Button>
        </div>
        <nav aria-label="Account resources" className="flex flex-wrap gap-6">
          {[
            ['/support', 'Support'],
            ['/privacy', 'Privacy policy'],
            ['/terms', 'Terms of service'],
          ].map(([href, label]) => (
            <Link
              key={href}
              href={href}
              className="focus-visible:outline-focus inline-flex min-h-11 items-center underline underline-offset-4 focus-visible:outline-2"
            >
              {label}
            </Link>
          ))}
        </nav>
      </section>
    </MarketingPage>
  );
}
