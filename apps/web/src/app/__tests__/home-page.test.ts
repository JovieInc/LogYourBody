import { getPricingPlanNote, landingSectionHeadings } from '../home-page-copy';

describe('HomePage landing copy', () => {
  it('keeps the System B section headings wired to the homepage module', () => {
    expect(landingSectionHeadings).toEqual({
      hero: 'LogYourBody',
      photos: 'The mirror gets a memory.',
      features: 'Everything important. Nothing noisy.',
      timeline: 'Your body over time.',
      pricing: 'Start with one clean body log.',
    });
  });

  it('returns pricing notes for annual and monthly states', () => {
    expect(getPricingPlanNote(true)).toBe('$5.83/month equivalent. Save 42%.');
    expect(getPricingPlanNote(false)).toBe('Switch anytime when you are ready.');
  });
});
