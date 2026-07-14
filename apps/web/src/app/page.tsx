import { cookies } from 'next/headers';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import {
  isLandingAudience,
  isLandingGoal,
  resolveLandingVariant,
  type LandingAssignmentSource,
} from '@/lib/marketing/landing-registry';
import { ExperimentWaitlistLanding } from './ExperimentWaitlistLanding';
import { FullLandingPage } from './FullLandingPage';
import { MinimalWaitlistLanding } from './MinimalWaitlistLanding';

type HomeSearchParams = Promise<Record<string, string | string[] | undefined>>;

const landingStructuredData = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'LogYourBody',
  applicationCategory: 'HealthApplication',
  operatingSystem: 'iOS',
  description: 'A private iPhone timeline for weight, body fat, lean mass, and progress photos.',
  url: 'https://logyourbody.com/',
};

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function HomePage({ searchParams }: { searchParams: HomeSearchParams }) {
  if (LANDING_FLAGS.WAITLIST_V2_ENABLED) {
    const params = await searchParams;
    const cookieStore = await cookies();
    const internalAudience = firstValue(params._lyb_audience);
    const requestedAudience = firstValue(params.audience);
    const storedAudience = cookieStore.get('lyb_landing_audience_v1')?.value;
    const audience = isLandingAudience(internalAudience)
      ? internalAudience
      : isLandingAudience(requestedAudience)
        ? requestedAudience
        : isLandingAudience(storedAudience)
          ? storedAudience
          : 'men';
    const requestedGoal = firstValue(params.goal);
    const goal = isLandingGoal(requestedGoal) ? requestedGoal : 'recomposition';
    const internalSource = firstValue(params._lyb_assignment_source);
    const assignmentSource: LandingAssignmentSource =
      internalSource === 'campaign' || internalSource === 'returning'
        ? internalSource
        : 'experiment';

    return (
      <>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(landingStructuredData) }}
        />
        <ExperimentWaitlistLanding
          variant={resolveLandingVariant({ audience, goal })}
          assignmentSource={assignmentSource}
        />
      </>
    );
  }

  if (LANDING_FLAGS.FULL_LANDING_ENABLED) {
    return <FullLandingPage />;
  }

  return <MinimalWaitlistLanding />;
}
