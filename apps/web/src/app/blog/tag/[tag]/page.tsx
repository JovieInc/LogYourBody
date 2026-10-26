import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import Link from 'next/link';
import { getAllTags, getPostsByTag } from '@/lib/blog';
import { MarketingPage } from '@/components/MarketingPage';
export const revalidate = false;
export async function generateStaticParams() {
  return (await getAllTags()).map((tag) => ({ tag: tag.toLowerCase().replace(/\s+/g, '-') }));
}
export async function generateMetadata({
  params,
}: {
  params: Promise<{ tag: string }>;
}): Promise<Metadata> {
  const { tag } = await params;
  const exactTag = (await getAllTags()).find(
    (value) => value.toLowerCase().replace(/\s+/g, '-') === tag,
  );
  if (!exactTag) notFound();
  return {
    title: `${exactTag} articles`,
    alternates: { canonical: `/blog/tag/${encodeURIComponent(tag)}` },
  };
}
export default async function TagPage({ params }: { params: Promise<{ tag: string }> }) {
  const { tag } = await params;
  const exactTag = (await getAllTags()).find(
    (value) => value.toLowerCase().replace(/\s+/g, '-') === tag,
  );
  if (!exactTag) notFound();
  const posts = await getPostsByTag(exactTag);
  return (
    <MarketingPage>
      <section className="max-w-prose-canonical space-y-6">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">{exactTag} articles</h1>
        <ul className="space-y-6">
          {posts.map((post) => (
            <li key={post.slug}>
              <Link className="text-lg underline underline-offset-4" href={`/blog/${post.slug}`}>
                {post.title}
              </Link>
            </li>
          ))}
        </ul>
        <Link
          href="/blog"
          className="inline-flex min-h-11 items-center underline underline-offset-4"
        >
          Back to articles
        </Link>
      </section>
    </MarketingPage>
  );
}
