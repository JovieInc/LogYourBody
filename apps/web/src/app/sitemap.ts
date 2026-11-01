import type { MetadataRoute } from 'next';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { endpoints } from '@/lib/generated/endpoints.generated';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const paths = [...PUBLIC_MARKETING_ROUTES];
  return paths.map((path) => ({
    url: new URL(path, endpoints.hosts.marketing.url).href,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : 0.5,
  }));
}
