import type { Metadata } from 'next';
import { logYourBody } from '@jovieinc/product-registry';
import { LaunchLanding } from './LaunchLanding';
import { endpoints } from '@/lib/generated/endpoints.generated';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { readEditorialHomepageRollout } from '@/lib/flags/publicLanding.server';

export const metadata: Metadata = {
  title: { absolute: `${logYourBody.identity.name} — ${logYourBody.brand.slogan}` },
  alternates: { canonical: '/' },
};

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

// A public launch switch can update without a client-side page swap or visitor tracking.
export const revalidate = 30;

export default async function HomePage() {
  const editorialEnabled =
    LANDING_FLAGS.ART_DIRECTION_V2_ENABLED && (await readEditorialHomepageRollout());
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(landingStructuredData).replace(/</g, '\\u003c'),
        }}
      />
      <LaunchLanding editorialEnabled={editorialEnabled} />
    </>
  );
}
