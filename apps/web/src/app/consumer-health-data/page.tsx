import { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { MarkdownRenderer } from '@/components/MarkdownRenderer';
import { loadLegalDocument } from '@/lib/load-legal-docs';

export const revalidate = false;

export const metadata: Metadata = {
  alternates: { canonical: '/consumer-health-data' },
  title: 'Consumer Health Data Privacy Policy',
  description:
    'How LogYourBody collects, uses, and shares consumer health data and how to exercise your rights.',
};

export default async function ConsumerHealthDataPage() {
  // Load the consumer health data policy markdown from shared documents
  const consumerHealthContent = await loadLegalDocument('consumerHealth');

  return (
    <MarketingPage>
      <div className="max-w-prose-canonical">
        <MarkdownRenderer content={consumerHealthContent} />
      </div>
    </MarketingPage>
  );
}
