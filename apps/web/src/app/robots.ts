import type { MetadataRoute } from 'next';

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
    sitemap: 'https://logyourbody.com/sitemap.xml',
    host: 'https://logyourbody.com',
  };
}
