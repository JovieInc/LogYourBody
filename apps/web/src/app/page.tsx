import { MinimalWaitlistLanding } from './MinimalWaitlistLanding';

const landingStructuredData = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': 'https://logyourbody.com/#organization',
      name: 'LogYourBody',
      url: 'https://logyourbody.com/',
      logo: 'https://logyourbody.com/brand/logyourbody-app-icon.png',
    },
    {
      '@type': 'WebSite',
      '@id': 'https://logyourbody.com/#website',
      name: 'LogYourBody',
      url: 'https://logyourbody.com/',
      publisher: { '@id': 'https://logyourbody.com/#organization' },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': 'https://logyourbody.com/#app',
      name: 'LogYourBody',
      applicationCategory: 'HealthApplication',
      operatingSystem: 'iOS',
      description:
        'A private iPhone timeline for weight, body fat, lean mass, and progress photos.',
      url: 'https://logyourbody.com/',
      publisher: { '@id': 'https://logyourbody.com/#organization' },
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
      <MinimalWaitlistLanding />
    </>
  );
}
