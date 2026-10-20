import { Metadata } from 'next'
import { Footer } from '@/components/Footer'
import { Header } from '@/components/Header'
import { MarkdownRenderer } from '@/components/MarkdownRenderer'
import { loadLegalDocument } from '@/lib/load-legal-docs'

export const metadata: Metadata = {
  title: 'Terms of Service - LogYourBody',
  description: 'LogYourBody terms of service and user agreement.',
}

export default async function TermsPage() {
  // Load the terms of service markdown from shared documents
  const termsContent = await loadLegalDocument('terms');

  return (
    <div className="min-h-screen bg-linear-bg">
      <Header />

      {/* Main Content */}
      <main className="container mx-auto px-4 py-16 max-w-4xl">
        <MarkdownRenderer content={termsContent} />
      </main>

      <Footer />
    </div>
  )
}