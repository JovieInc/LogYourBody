import { Metadata } from 'next'
import Link from 'next/link'
import { Mail, MessageCircle, FileText, ExternalLink } from 'lucide-react'
import { Header } from '@/components/Header'
import { Footer } from '@/components/Footer'

export const metadata: Metadata = {
  title: 'Support - LogYourBody',
  description: 'Get help with LogYourBody. Contact our support team, browse FAQs, or find resources.',
}

export default function SupportPage() {
  return (
    <div className="min-h-screen bg-black flex flex-col">
      <Header />
      <main className="flex-1">
        <div className="max-w-4xl mx-auto px-4 py-16 sm:px-6 lg:px-8">
          {/* Header */}
          <div className="text-center mb-12">
            <h1 className="text-4xl font-semibold text-white mb-4">
              How can we help?
            </h1>
            <p className="text-lg text-gray-400">
              We're here to help you get the most out of LogYourBody
            </p>
          </div>

          {/* Support Options */}
          <div className="grid md:grid-cols-2 gap-6 mb-12">
            {/* Email Support */}
            <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
              <div className="flex items-center mb-4">
                <Mail className="w-6 h-6 text-white mr-3" />
                <h2 className="text-xl font-medium text-white">Email Support</h2>
              </div>
              <p className="text-gray-400 mb-4">
                Get help from our support team. We typically respond within 24 hours.
              </p>
              <a
                href="mailto:support@logyourbody.com"
                className="inline-flex items-center text-white hover:text-gray-300 transition-colors"
              >
                support@logyourbody.com
                <ExternalLink className="w-4 h-4 ml-2" />
              </a>
              <p className="text-sm text-gray-400 mt-3">
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
                      'Thank you,'
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
            <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
              <div className="flex items-center mb-4">
                <MessageCircle className="w-6 h-6 text-white mr-3" />
                <h2 className="text-xl font-medium text-white">Community</h2>
              </div>
              <p className="text-gray-400 mb-4">
                Join our community to connect with other users and get tips.
              </p>
              <a
                href="https://reddit.com/r/logyourbody"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center text-white hover:text-gray-300 transition-colors"
              >
                Visit Community
                <ExternalLink className="w-4 h-4 ml-2" />
              </a>
            </div>
          </div>

          {/* Quick Links */}
          <div className="bg-gray-900 rounded-lg p-8 border border-gray-800 mb-12">
            <h2 className="text-2xl font-medium text-white mb-6">Quick Links</h2>
            <div className="grid sm:grid-cols-2 gap-4">
              <Link
                href="/privacy"
                className="flex items-center text-gray-400 hover:text-white transition-colors"
              >
                <FileText className="w-5 h-5 mr-3" />
                Privacy Policy
              </Link>
              <Link
                href="/terms"
                className="flex items-center text-gray-400 hover:text-white transition-colors"
              >
                <FileText className="w-5 h-5 mr-3" />
                Terms of Service
              </Link>
              <Link
                href="/changelog"
                className="flex items-center text-gray-400 hover:text-white transition-colors"
              >
                <FileText className="w-5 h-5 mr-3" />
                Changelog
              </Link>
              <Link
                href="/download"
                className="flex items-center text-gray-400 hover:text-white transition-colors"
              >
                <FileText className="w-5 h-5 mr-3" />
                Download Apps
              </Link>
            </div>
          </div>

          {/* FAQs */}
          <div className="mb-12">
            <h2 className="text-2xl font-medium text-white mb-6">Frequently Asked Questions</h2>
            <div className="space-y-6">
              <div>
                <h3 className="text-lg font-medium text-white mb-2">
                  How do I sync my data across devices?
                </h3>
                <p className="text-gray-400">
                  Your data automatically syncs across all devices when you're signed in with the same account.
                  Make sure you have an internet connection for syncing to work.
                </p>
              </div>

              <div>
                <h3 className="text-lg font-medium text-white mb-2">
                  How do I export my data?
                </h3>
                <p className="text-gray-400">
                  You can export your data from the Settings page. Go to Settings → Account → Export Data.
                  Your data will be downloaded as a CSV file.
                </p>
              </div>

              <div>
                <h3 className="text-lg font-medium text-white mb-2">
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
                <h3 className="text-lg font-medium text-white mb-2">
                  How do I delete my account?
                </h3>
                <p className="text-gray-400">
                  You can delete your account from the Settings page. Go to Settings → Account → Delete Account.
                  Please note that this action is permanent and cannot be undone.
                </p>
              </div>
            </div>
          </div>

          {/* Contact Form Placeholder */}
          <div className="bg-gray-900 rounded-lg p-8 border border-gray-800">
            <h2 className="text-2xl font-medium text-white mb-4">Need more help?</h2>
            <p className="text-gray-400 mb-6">
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
  )
}