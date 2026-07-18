import React from 'react';
import Link from 'next/link';
import { APP_CONFIG } from '@/constants/app';
import { logYourBody } from '@jovieinc/product-registry';

export function Footer() {
  return (
    <footer className="relative overflow-hidden border-t border-gray-800/50 bg-black">
      {/* Gradient overlay for depth */}
      <div className="absolute inset-0 bg-gradient-to-b from-gray-900/5 to-black/50" />

      <div className="relative">
        <div className="mx-auto max-w-7xl px-6 py-12 lg:px-8 lg:py-16">
          <div className="grid grid-cols-2 gap-8 md:grid-cols-4 lg:gap-x-12">
            {/* Logo and tagline */}
            <div className="col-span-2 md:col-span-1">
              <Link href="/" className="inline-flex items-center space-x-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/10 backdrop-blur-sm">
                  <svg
                    className="h-5 w-5 text-white"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M3 3v18h18" />
                    <path d="m19 9-5 5-4-4-3 3" />
                  </svg>
                </div>
                <span className="text-lg font-medium text-white">{APP_CONFIG.appName}</span>
              </Link>
              <p className="mt-4 text-sm leading-relaxed text-gray-400">
                {logYourBody.brand.slogan}
              </p>

              {/* GitHub link */}
              <a
                href={APP_CONFIG.social.github}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-6 inline-flex rounded-lg p-2 text-gray-400 transition hover:bg-white/5 hover:text-white"
                aria-label="GitHub"
              >
                <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24">
                  <path
                    fillRule="evenodd"
                    d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
                    clipRule="evenodd"
                  />
                </svg>
              </a>
            </div>

            {/* Product & Resources */}
            <div>
              <h3 className="text-sm font-medium text-white">Product</h3>
              <ul className="mt-4 space-y-3">
                <li>
                  <Link
                    href="/#features"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Features
                  </Link>
                </li>
                <li>
                  <Link
                    href="/#pricing"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Pricing
                  </Link>
                </li>
                <li>
                  <Link
                    href="/download"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Download
                  </Link>
                </li>
                <li>
                  <Link
                    href="/changelog"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    What's New
                  </Link>
                </li>
                <li>
                  <Link href="/blog" className="text-sm text-gray-400 transition hover:text-white">
                    Blog
                  </Link>
                </li>
              </ul>
            </div>

            {/* Support */}
            <div>
              <h3 className="text-sm font-medium text-white">Support</h3>
              <ul className="mt-4 space-y-3">
                <li>
                  <Link
                    href="/support"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Help Center
                  </Link>
                </li>
                <li>
                  <a
                    href={`mailto:${APP_CONFIG.contact.support}`}
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Contact Us
                  </a>
                </li>
                <li>
                  <a
                    href={logYourBody.links.status}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    System Status
                  </a>
                </li>
                <li>
                  <Link
                    href="/security"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Security
                  </Link>
                </li>
              </ul>
            </div>

            {/* Legal */}
            <div>
              <h3 className="text-sm font-medium text-white">Legal</h3>
              <ul className="mt-4 space-y-3">
                <li>
                  <Link
                    href="/privacy"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Privacy Policy
                  </Link>
                </li>
                <li>
                  <Link href="/terms" className="text-sm text-gray-400 transition hover:text-white">
                    Terms of Service
                  </Link>
                </li>
                <li>
                  <Link
                    href="/health-disclosure"
                    className="text-sm text-gray-400 transition hover:text-white"
                  >
                    Health Disclosure
                  </Link>
                </li>
              </ul>
            </div>
          </div>

          {/* Bottom section - simplified */}
          <div className="mt-12 border-t border-gray-800/50 pt-8">
            <p className="text-center text-sm text-gray-400">
              © {new Date().getFullYear()} {APP_CONFIG.companyName}. All rights reserved.
            </p>
          </div>
        </div>
      </div>
    </footer>
  );
}

export default Footer;
