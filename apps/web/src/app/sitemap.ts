import type { MetadataRoute } from 'next';

const publicRoutes = ['', '/privacy', '/terms', '/health-disclosure', '/support'] as const;

export default function sitemap(): MetadataRoute.Sitemap {
  return publicRoutes.map((path, index) => ({
    url: `https://logyourbody.com${path}`,
    lastModified: new Date(),
    changeFrequency: index === 0 ? 'weekly' : 'monthly',
    priority: index === 0 ? 1 : 0.5,
  }));
}
