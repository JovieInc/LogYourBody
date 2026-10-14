import Link from 'next/link';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';
export default function NotFound() {
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">Page not found</h1>
        <p className="text-secondary-token text-lg leading-8">
          This page is unavailable. You can return to LogYourBody or contact support.
        </p>
        <div className="flex flex-wrap gap-6 py-2">
          <Button asChild size="marketing">
            <Link href="/">Go home</Link>
          </Button>
          <Button asChild variant="secondary" size="marketing">
            <Link href="/support">Contact support</Link>
          </Button>
        </div>
      </section>
    </MarketingPage>
  );
}
