import type { MetadataRoute } from 'next';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { getAllPosts } from '@/lib/blog';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  // Use the same publication boundary as article pages; drafts remain excluded.
  const posts = await getAllPosts();
  const paths = [
    ...PUBLIC_MARKETING_ROUTES,
    ...posts.map((post) => `/blog/${encodeURIComponent(post.slug)}`),
  ];
  return paths.map((path) => ({
    url: new URL(path, endpoints.hosts.marketing.url).href,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : 0.5,
  }));
}
