import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getAllSlugs, getPostBySlug } from '@/lib/blog';
import { MarketingPage } from '@/components/MarketingPage';
import { MarkdownRenderer } from '@/components/MarkdownRenderer';
export const revalidate = false;
type Props = { params: Promise<{ slug: string }> };
export async function generateStaticParams() {
  return (await getAllSlugs()).map((slug) => ({ slug }));
}
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPostBySlug(slug);
  return post
    ? {
        title: post.title,
        description: post.excerpt,
        alternates: { canonical: `/blog/${encodeURIComponent(slug)}` },
      }
    : { title: 'Article unavailable' };
}
export default async function BlogPostPage({ params }: Props) {
  const post = await getPostBySlug((await params).slug);
  if (!post) notFound();
  return (
    <MarketingPage>
      <article className="max-w-prose-canonical space-y-8">
        <h1 className="text-4xl leading-tight font-bold sm:text-5xl">{post.title}</h1>
        <p className="text-tertiary-token text-sm">
          {post.author} · {post.formattedDate}
        </p>
        <MarkdownRenderer content={post.content} />
        <Link
          href="/blog"
          className="inline-flex min-h-11 items-center underline underline-offset-4"
        >
          Back to articles
        </Link>
      </article>
    </MarketingPage>
  );
}
