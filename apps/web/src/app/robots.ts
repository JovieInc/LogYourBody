import type { MetadataRoute } from 'next';
import { endpoints } from '@/lib/generated/endpoints.generated';

const marketingUrl = endpoints.hosts.marketing.url;

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: '*',
      allow: '/',
      disallow: [
        '/dashboard/',
        '/import/',
        '/log/',
        '/onboarding/',
        '/photos/',
        '/settings/',
        '/steps/',
        '/api/',
      ],
    },
    sitemap: `${marketingUrl}/sitemap.xml`,
    host: marketingUrl,
  };
}
