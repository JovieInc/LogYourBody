import { Metadata } from 'next';
import Link from 'next/link';
import { Mail, FileText, ExternalLink } from 'lucide-react';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { getPublicSupportOptions, logYourBody } from '@jovieinc/product-registry';

export const metadata: Metadata = {
  title: `Support - ${logYourBody.identity.name}`,
  description: `Get help with ${logYourBody.identity.name}, your account, subscription, or data.`,
};

export default function SupportPage() {
  return (
    <div className="flex min-h-screen flex-col bg-black">
      <Header />
      <main className="flex-1">
        <div className="mx-auto max-w-4xl px-4 py-16 sm:px-6 lg:px-8">
          {/* Header */}
          <div className="mb-12 text-center">
            <h1 className="mb-4 text-4xl font-semibold text-white">How can we help?</h1>
            <p className="text-lg text-gray-400">
              Get help with {logYourBody.identity.name}, your account, subscription, or data.
            </p>
          </div>

          {/* Support Options */}
          <div className="mb-12 grid gap-6 md:grid-cols-2">
            {getPublicSupportOptions().map((option) => (
              <div key={option.id} className="rounded-lg border border-gray-800 bg-gray-900 p-6">
                <div className="mb-4 flex items-center">
                  {option.kind === 'email' ? (
                    <Mail className="mr-3 h-6 w-6 text-white" />
                  ) : (
                    <FileText className="mr-3 h-6 w-6 text-white" />
                  )}
                  <h2 className="text-xl font-medium text-white">{option.label}</h2>
                </div>
                <p className="mb-4 text-gray-400">{option.description}</p>
                <a
                  href={option.href}
                  className="inline-flex items-center text-white transition-colors hover:text-gray-300"
                >
                  {option.kind === 'email' ? logYourBody.contacts.support : option.label}
                  <ExternalLink className="ml-2 h-4 w-4" />
                </a>
                {'responseTime' in option && option.responseTime ? (
                  <p className="mt-3 text-sm text-gray-500">{option.responseTime}</p>
                ) : null}
              </div>
            ))}
          </div>

          {/* Quick Links */}
          <div className="mb-12 rounded-lg border border-gray-800 bg-gray-900 p-8">
            <h2 className="mb-6 text-2xl font-medium text-white">Quick Links</h2>
            <div className="grid gap-4 sm:grid-cols-2">
              <Link
                href="/privacy"
                className="flex items-center text-gray-400 transition-colors hover:text-white"
              >
                <FileText className="mr-3 h-5 w-5" />
                Privacy Policy
              </Link>
              <Link
                href="/terms"
                className="flex items-center text-gray-400 transition-colors hover:text-white"
              >
                <FileText className="mr-3 h-5 w-5" />
                Terms of Service
              </Link>
              <Link
                href="/changelog"
                className="flex items-center text-gray-400 transition-colors hover:text-white"
              >
                <FileText className="mr-3 h-5 w-5" />
                Changelog
              </Link>
              <Link
                href="/download"
                className="flex items-center text-gray-400 transition-colors hover:text-white"
              >
                <FileText className="mr-3 h-5 w-5" />
                Download Apps
              </Link>
              <Link
                href="/delete-account"
                className="flex items-center text-gray-400 transition-colors hover:text-white"
              >
                <FileText className="mr-3 h-5 w-5" />
                Delete Account
              </Link>
            </div>
          </div>

          {/* FAQs */}
          <div className="mb-12">
            <h2 className="mb-6 text-2xl font-medium text-white">Frequently Asked Questions</h2>
            <div className="space-y-6">
              <div>
                <h3 className="mb-2 text-lg font-medium text-white">
                  How do I sync my data across devices?
                </h3>
                <p className="text-gray-400">
                  Your data automatically syncs across all devices when you're signed in with the
                  same account. Make sure you have an internet connection for syncing to work.
                </p>
              </div>

              <div>
                <h3 className="mb-2 text-lg font-medium text-white">How do I export my data?</h3>
                <p className="text-gray-400">
                  You can export your data from the Settings page. Go to Settings → Account → Export
                  Data. Your data will be downloaded as a CSV file.
                </p>
              </div>

              <div>
                <h3 className="mb-2 text-lg font-medium text-white">
                  Is my data private and secure?
                </h3>
                <p className="text-gray-400">
                  Yes, we take your privacy seriously. All data is encrypted in transit and at rest.
                  We never share your personal data with third parties. Read our{' '}
                  <Link href="/privacy" className="text-white hover:text-gray-300">
                    Privacy Policy
                  </Link>{' '}
                  for more details.
                </p>
              </div>

              <div>
                <h3 className="mb-2 text-lg font-medium text-white">How do I delete my account?</h3>
                <p className="text-gray-400">
                  You can delete your account from the Settings page. Go to Settings → Account →
                  Delete Account. Please note that this action is permanent and cannot be undone.
                  See the{' '}
                  <Link href="/delete-account" className="text-white hover:text-gray-300">
                    account deletion page
                  </Link>{' '}
                  for details and the email support fallback.
                </p>
              </div>
            </div>
          </div>

          {/* Contact Form Placeholder */}
          <div className="rounded-lg border border-gray-800 bg-gray-900 p-8">
            <h2 className="mb-4 text-2xl font-medium text-white">Need more help?</h2>
            <p className="mb-6 text-gray-400">
              If you couldn't find what you're looking for, please email us at{' '}
              <a
                href={`mailto:${logYourBody.contacts.support}`}
                className="text-white hover:text-gray-300"
              >
                {logYourBody.contacts.support}
              </a>{' '}
              and we'll get back to you as soon as possible.
            </p>
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}
