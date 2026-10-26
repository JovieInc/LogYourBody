import { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { MarkdownRenderer } from '@/components/MarkdownRenderer';
import { loadLegalDocument } from '@/lib/load-legal-docs';

export const revalidate = false;

export const metadata: Metadata = {
  alternates: { canonical: '/privacy' },
  title: 'Privacy Policy',
  description: 'LogYourBody privacy policy - Learn how we protect and handle your data.',
};

export default async function PrivacyPage() {
  // Load the privacy policy markdown from shared documents
  const privacyContent = await loadLegalDocument('privacy');

  return (
    <MarketingPage>
      <div className="max-w-prose-canonical">
        <MarkdownRenderer content={privacyContent} />
      </div>
    </MarketingPage>
  );
}
