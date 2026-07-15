import budget from '../../../performance-budgets.json';

describe('marketing performance budget', () => {
  it('keeps explicit launch thresholds in source control', () => {
    expect(budget.route).toBe('/');
    expect(budget.lighthouse.performance).toBeGreaterThanOrEqual(0.95);
    expect(budget.lighthouse.accessibility).toBeGreaterThanOrEqual(0.95);
    expect(budget.webVitalsP75.lcpMs).toBeLessThanOrEqual(2_500);
    expect(budget.webVitalsP75.inpMs).toBeLessThanOrEqual(200);
    expect(budget.webVitalsP75.cls).toBeLessThanOrEqual(0.1);
    expect(budget.transfer.compressedJavaScriptBytes).toBeLessThanOrEqual(153_600);
    expect(budget.transfer.initialPageBytes).toBeLessThanOrEqual(512_000);
  });
});
