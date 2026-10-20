import { Metadata } from 'next'
import { Footer } from '@/components/Footer'
import { Header } from '@/components/Header'
import { MarkdownRenderer } from '@/components/MarkdownRenderer'
import { loadLegalDocument } from '@/lib/load-legal-docs'

export const metadata: Metadata = {
  title: 'Health Disclosure - LogYourBody',
  description: 'Important health and medical information about using LogYourBody.',
}

export default async function HealthDisclosurePage() {
  // Load the health disclosure markdown from shared documents
  const healthContent = await loadLegalDocument('health');

  return (
    <div className="min-h-screen bg-linear-bg">
      <Header />

      {/* Main Content */}
      <main className="container mx-auto px-4 py-16 max-w-4xl">
        <MarkdownRenderer content={healthContent} />
      </main>

      <Footer />
    </div>
  )
}