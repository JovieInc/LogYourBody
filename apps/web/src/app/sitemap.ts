import type { MetadataRoute } from 'next';
import { PUBLIC_MARKETING_ROUTES } from '@/data/publicMarketingRoutes';
import { endpoints } from '@/lib/generated/endpoints.generated';

export default function sitemap(): MetadataRoute.Sitemap {
  return PUBLIC_MARKETING_ROUTES.map((path) => ({
    url: `${endpoints.hosts.marketing.url}${path === '/' ? '' : path}`,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : 0.5,
  }));
}
