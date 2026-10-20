import { LaunchLanding } from './LaunchLanding';
import { endpoints } from '@/lib/generated/endpoints.generated';

const marketingUrl = endpoints.hosts.marketing.url;

const landingStructuredData = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': `${marketingUrl}/#organization`,
      name: 'LogYourBody',
      url: `${marketingUrl}/`,
      logo: `${marketingUrl}/brand/logyourbody-app-icon.png`,
    },
    {
      '@type': 'WebSite',
      '@id': `${marketingUrl}/#website`,
      name: 'LogYourBody',
      url: `${marketingUrl}/`,
      publisher: { '@id': `${marketingUrl}/#organization` },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': `${marketingUrl}/#app`,
      name: 'LogYourBody',
      applicationCategory: 'HealthApplication',
      operatingSystem: 'iOS',
      description:
        'A private iPhone timeline for weight, body fat, lean mass, and progress photos.',
      url: `${marketingUrl}/`,
      publisher: { '@id': `${marketingUrl}/#organization` },
    },
  ],
};

export default function HomePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(landingStructuredData).replace(/</g, '\\u003c'),
        }}
      />
      <LaunchLanding />
    </>
  );
}
