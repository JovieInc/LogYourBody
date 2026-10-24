import { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { MarkdownRenderer } from '@/components/MarkdownRenderer';
import { loadLegalDocument } from '@/lib/load-legal-docs';

export const revalidate = false;

export const metadata: Metadata = {
  alternates: { canonical: '/terms' },
  title: 'Terms of Service',
  description: 'LogYourBody terms of service and user agreement.',
};

export default async function TermsPage() {
  // Load the terms of service markdown from shared documents
  const termsContent = await loadLegalDocument('terms');

  return (
    <MarketingPage>
      <div className="max-w-prose-canonical">
        <MarkdownRenderer content={termsContent} />
      </div>
    </MarketingPage>
  );
}
