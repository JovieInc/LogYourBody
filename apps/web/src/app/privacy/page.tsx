import { Metadata } from 'next'
import { Footer } from '@/components/Footer'
import { Header } from '@/components/Header'
import { MarkdownRenderer } from '@/components/MarkdownRenderer'
import { loadLegalDocument } from '@/lib/load-legal-docs'

export const metadata: Metadata = {
  title: 'Privacy Policy - LogYourBody',
  description: 'LogYourBody privacy policy - Learn how we protect and handle your data.',
}

export default async function PrivacyPage() {
  // Load the privacy policy markdown from shared documents
  const privacyContent = await loadLegalDocument('privacy');

  return (
    <div className="min-h-screen bg-linear-bg">
      <Header />

      {/* Main Content */}
      <main className="container mx-auto px-4 py-16 max-w-4xl">
        <MarkdownRenderer content={privacyContent} />
      </main>

      <Footer />
    </div>
  )
}