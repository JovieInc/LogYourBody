import { generateMetadata } from '../[slug]/page';
import { getPostBySlug } from '@/lib/blog';
import { notFound } from 'next/navigation';

jest.mock('@/lib/blog', () => ({
  getPostBySlug: jest.fn(),
  getAllSlugs: jest.fn(),
}));
jest.mock('next/navigation', () => ({
  notFound: jest.fn(() => {
    throw new Error('NEXT_NOT_FOUND');
  }),
}));
jest.mock('@/components/MarketingPage', () => ({ MarketingPage: () => null }));
jest.mock('@/components/MarkdownRenderer', () => ({ MarkdownRenderer: () => null }));

describe('published article search and social metadata', () => {
  it('shares the article title and description instead of inheriting homepage copy', async () => {
    jest.mocked(getPostBySlug).mockResolvedValue({
      slug: 'progress & context',
      title: 'Understanding your progress',
      excerpt: 'How to read a longer-term trend.',
      author: 'LogYourBody Team',
      tags: ['Progress'],
    } as NonNullable<Awaited<ReturnType<typeof getPostBySlug>>>);
    const metadata = await generateMetadata({
      params: Promise.resolve({ slug: 'progress & context' }),
    });
    expect(metadata.alternates).toEqual({ canonical: '/blog/progress%20%26%20context' });
    expect(metadata.openGraph).toMatchObject({
      type: 'article',
      title: 'Understanding your progress',
      description: 'How to read a longer-term trend.',
      url: '/blog/progress%20%26%20context',
      authors: ['LogYourBody Team'],
      tags: ['Progress'],
    });
    expect(metadata.twitter).toMatchObject({
      title: 'Understanding your progress',
      description: 'How to read a longer-term trend.',
    });
    expect(metadata.openGraph).not.toHaveProperty('publishedTime');
  });

  it('keeps drafts and missing articles out of discoverable metadata', async () => {
    jest.mocked(getPostBySlug).mockResolvedValue(null);
    await expect(generateMetadata({ params: Promise.resolve({ slug: 'draft' }) })).rejects.toThrow(
      'NEXT_NOT_FOUND',
    );
    expect(notFound).toHaveBeenCalled();
  });
});
