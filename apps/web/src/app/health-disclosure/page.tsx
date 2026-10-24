import { Metadata } from 'next';
import { MarketingPage } from '@/components/MarketingPage';
import { MarkdownRenderer } from '@/components/MarkdownRenderer';
import { loadLegalDocument } from '@/lib/load-legal-docs';

export const revalidate = false;

export const metadata: Metadata = {
  alternates: { canonical: '/health-disclosure' },
  title: 'Health Disclosure',
  description: 'Important health and medical information about using LogYourBody.',
};

export default async function HealthDisclosurePage() {
  // Load the health disclosure markdown from shared documents
  const healthContent = await loadLegalDocument('health');

  return (
    <MarketingPage>
      <div className="max-w-prose-canonical">
        <MarkdownRenderer content={healthContent} />
      </div>
    </MarketingPage>
  );
}
