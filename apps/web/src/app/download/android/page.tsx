import type { Metadata } from 'next';
import Link from 'next/link';
import { Button } from '@jovie/ui/atoms/button';
import { MarketingPage } from '@/components/MarketingPage';

export const revalidate = false;

export const metadata: Metadata = {
  title: 'Android availability',
  description: 'LogYourBody is an iPhone app. There is no Android release available.',
};
export default function AndroidDownloadPage() {
  return (
    <MarketingPage>
      <section className="max-w-[680px] space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">LogYourBody is for iPhone</h1>
        <p className="text-secondary-token text-lg leading-8">
          There is no Android release available. We have no Android release date to announce.
        </p>
        <Button asChild size="marketing" className="my-2">
          <Link href="/download/ios">Explore iPhone early access</Link>
        </Button>
      </section>
    </MarketingPage>
  );
}
