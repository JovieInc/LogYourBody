import type { Metadata } from 'next';
import Link from 'next/link';
import { getAllPosts } from '@/lib/blog';
import { MarketingPage } from '@/components/MarketingPage';
export const revalidate = false;
export const metadata: Metadata = {
  alternates: { canonical: '/blog' },
  title: 'Articles',
  description: 'Articles from LogYourBody.',
};
export default async function BlogPage() {
  const posts = await getAllPosts();
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">Articles</h1>
        {posts.length ? (
          <ul className="divide-subtle divide-y">
            {posts.map((post) => (
              <li key={post.slug} className="space-y-3 py-8">
                <h2 className="text-2xl font-semibold">
                  <Link href={`/blog/${post.slug}`} className="underline underline-offset-4">
                    {post.title}
                  </Link>
                </h2>
                <p className="text-secondary-token text-base leading-7">{post.excerpt}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-secondary-token text-lg leading-8">No published articles yet.</p>
        )}
      </section>
    </MarketingPage>
  );
}
