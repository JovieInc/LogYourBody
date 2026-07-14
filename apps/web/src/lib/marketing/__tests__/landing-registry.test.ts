import {
  buildLandingSource,
  LANDING_EXPERIMENTS,
  LANDING_PRODUCT_PROOF,
  resolveLandingVariant,
} from '../landing-registry';
import { evaluateLandingSystem } from '../landing-evaluation';

describe('landing marketing registry', () => {
  it('passes the blocking configuration evaluation', () => {
    expect(evaluateLandingSystem()).toEqual(
      expect.objectContaining({
        score: 100,
        passed: true,
      }),
    );
    expect(Object.values(evaluateLandingSystem().hardGates)).not.toContain(false);
  });

  it('resolves men and women creative without changing the core layout copy', () => {
    const men = resolveLandingVariant({ audience: 'men', goal: 'recomposition' });
    const women = resolveLandingVariant({ audience: 'women', goal: 'recomposition' });

    expect(men.heroImage).not.toBe(women.heroImage);
    expect(men.headline).toBe(women.headline);
    expect(men.subheading).toBe(women.subheading);
  });

  it('keeps goal messaging in data rather than separate page implementations', () => {
    expect(resolveLandingVariant({ goal: 'fat-loss' }).headline).toMatch(/cut/i);
    expect(resolveLandingVariant({ goal: 'muscle-gain' }).headline).toMatch(/gain/i);
    expect(resolveLandingVariant({ goal: 'unknown' }).goal).toBe('recomposition');
  });

  it('declares a bounded first experiment and a sequential planned goal test', () => {
    expect(LANDING_EXPERIMENTS.audienceCreativeV1).toEqual(
      expect.objectContaining({
        status: 'active',
        sampleSizePerArm: 903,
        allocation: { men: 50, women: 50 },
      }),
    );
    expect(LANDING_EXPERIMENTS.goalMessageV1.status).toBe('planned');
  });

  it('attributes waitlist sources without putting email or other PII in the label', () => {
    expect(
      buildLandingSource({
        audience: 'women',
        goal: 'fat-loss',
        assignmentSource: 'campaign',
      }),
    ).toBe('landing:v2:women:fat-loss:campaign');
  });

  it('uses only the canonical real-app screenshot registry entry for product proof', () => {
    expect(LANDING_PRODUCT_PROOF.sourceKind).toBe('ios-fastlane-capture');
    expect(LANDING_PRODUCT_PROOF.truthStatus).toBe('real-app-capture');
    expect(LANDING_PRODUCT_PROOF.src).toBe('/product-screenshots/ios/weight-log.png');
  });
});
