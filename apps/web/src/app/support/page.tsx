import { Metadata } from 'next';
import Link from 'next/link';
import { Mail, MessageCircle, FileText, ExternalLink } from 'lucide-react';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';

export const metadata: Metadata = {
  title: 'Support - LogYourBody',
  description:
    'Get help with LogYourBody. Contact our support team, browse FAQs, or find resources.',
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
              We're here to help you get the most out of LogYourBody
            </p>
          </div>

          {/* Support Options */}
          <div className="mb-12 grid gap-6 md:grid-cols-2">
            {/* Email Support */}
            <div className="rounded-lg border border-gray-800 bg-gray-900 p-6">
              <div className="mb-4 flex items-center">
                <Mail className="mr-3 h-6 w-6 text-white" />
                <h2 className="text-xl font-medium text-white">Email Support</h2>
              </div>
              <p className="mb-4 text-gray-400">
                Get help from our support team. We typically respond within 24 hours.
              </p>
              <a
                href="mailto:support@logyourbody.com"
                className="inline-flex items-center text-white transition-colors hover:text-gray-300"
              >
                support@logyourbody.com
                <ExternalLink className="ml-2 h-4 w-4" />
              </a>
              <p className="mt-3 text-sm text-gray-400">
                Want a copy of your data?{' '}
                <a
                  href={
                    'mailto:support@logyourbody.com' +
                    '?subject=' +
                    encodeURIComponent('LogYourBody Data Export Request') +
                    '&body=' +
                    encodeURIComponent(
                      'Hello LogYourBody Support,\n\n' +
                        'I would like to request an export of my LogYourBody account data associated with this email address.\n\n' +
                        'Thank you,',
                    )
                  }
                  className="text-white underline hover:text-gray-300"
                >
                  Request a data export by email
                </a>
                .
              </p>
            </div>

            {/* Community */}
            <div className="rounded-lg border border-gray-800 bg-gray-900 p-6">
              <div className="mb-4 flex items-center">
                <MessageCircle className="mr-3 h-6 w-6 text-white" />
                <h2 className="text-xl font-medium text-white">Community</h2>
              </div>
              <p className="mb-4 text-gray-400">
                Join our community to connect with other users and get tips.
              </p>
              <a
                href="https://reddit.com/r/logyourbody"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center text-white transition-colors hover:text-gray-300"
              >
                Visit Community
                <ExternalLink className="ml-2 h-4 w-4" />
              </a>
            </div>
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
              <a href="mailto:support@logyourbody.com" className="text-white hover:text-gray-300">
                support@logyourbody.com
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
