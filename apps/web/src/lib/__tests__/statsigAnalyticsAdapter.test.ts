import { createStatsigAnalytics } from '../statsigAnalyticsAdapter';

describe('createStatsigAnalytics', () => {
    it('exposes analytics port methods', () => {
        const analytics = createStatsigAnalytics({ clientKey: '' });

        expect(analytics.identify).toBeDefined();
        expect(analytics.track).toBeDefined();
        expect(analytics.reset).toBeDefined();
        expect(analytics.isFeatureEnabled).toBeDefined();
    });

    it('no-ops safely when client key is missing', () => {
        const analytics = createStatsigAnalytics({ clientKey: '' });

        expect(() =>
            analytics.identify('user-1', {
                plan: 'pro',
                empty: null,
                count: 2,
                active: true,
            }),
        ).not.toThrow();

        expect(() =>
            analytics.track('app_open', {
                source: 'test',
                count: 1,
                enabled: true,
                skipped: null,
            }),
        ).not.toThrow();

        expect(analytics.isFeatureEnabled('flag')).toBe(false);
    });
});