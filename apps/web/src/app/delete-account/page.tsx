import { Metadata } from 'next';
import Link from 'next/link';
import { Download, Mail, ShieldCheck, Smartphone } from 'lucide-react';
import { Footer } from '@/components/Footer';
import { Header } from '@/components/Header';

const deletionRequestHref =
  'mailto:support@logyourbody.com' +
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

export default function DeleteAccountPage() {
  return (
    <div className="flex min-h-screen flex-col bg-black">
      <Header />
      <main className="flex-1">
        <section className="mx-auto max-w-4xl px-6 py-16 sm:py-20 lg:px-8">
          <div className="max-w-2xl">
            <p className="mb-4 text-sm font-medium text-white/50">Account deletion</p>
            <h1 className="mb-6 text-4xl font-semibold tracking-tight text-white sm:text-5xl">
              Delete your LogYourBody account
            </h1>
            <p className="text-lg leading-8 text-white/60">
              You can permanently delete your account from the iOS app. If you no longer have access
              to the app, support can help process the request by email.
            </p>
          </div>

          <div className="mt-12 grid gap-4 md:grid-cols-3">
            <div className="rounded-lg border border-white/10 bg-white/[0.03] p-6">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10">
                <Smartphone className="h-5 w-5 text-white" aria-hidden="true" />
              </div>
              <h2 className="text-base font-medium text-white">Open settings</h2>
              <p className="mt-3 text-sm leading-6 text-white/55">
                In the iOS app, go to Settings, then Account.
              </p>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/[0.03] p-6">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10">
                <ShieldCheck className="h-5 w-5 text-white" aria-hidden="true" />
              </div>
              <h2 className="text-base font-medium text-white">Confirm deletion</h2>
              <p className="mt-3 text-sm leading-6 text-white/55">
                Choose Delete Account and follow the confirmation prompts.
              </p>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/[0.03] p-6">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10">
                <Mail className="h-5 w-5 text-white" aria-hidden="true" />
              </div>
              <h2 className="text-base font-medium text-white">Need help?</h2>
              <p className="mt-3 text-sm leading-6 text-white/55">
                Email support if you cannot access the app or need help with your request.
              </p>
            </div>
          </div>

          <div className="mt-12 rounded-lg border border-white/10 bg-white/[0.03] p-6 sm:p-8">
            <h2 className="text-xl font-medium text-white">What happens next</h2>
            <div className="mt-5 space-y-4 text-sm leading-6 text-white/60">
              <p>
                Account deletion removes your LogYourBody account data and signs you out. This
                action is permanent and cannot be undone.
              </p>
              <p>
                If you request deletion by email, include the email address associated with your
                account so support can verify and process the request.
              </p>
            </div>

            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Link
                href="/download/ios"
                className="inline-flex items-center justify-center rounded-full bg-white px-5 py-3 text-sm font-medium text-black transition hover:bg-white/90"
              >
                <Download className="mr-2 h-4 w-4" aria-hidden="true" />
                Download iOS app
              </Link>
              <a
                href={deletionRequestHref}
                className="inline-flex items-center justify-center rounded-full border border-white/15 px-5 py-3 text-sm font-medium text-white transition hover:bg-white/10"
              >
                <Mail className="mr-2 h-4 w-4" aria-hidden="true" />
                Email support
              </a>
            </div>
          </div>

          <div className="mt-8 flex flex-wrap gap-x-6 gap-y-3 text-sm text-white/50">
            <Link href="/support" className="hover:text-white">
              Support
            </Link>
            <Link href="/privacy" className="hover:text-white">
              Privacy Policy
            </Link>
            <Link href="/terms" className="hover:text-white">
              Terms of Service
            </Link>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
