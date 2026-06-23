import { toStatsigCustomTraits, toStatsigEventMetadata } from '../statsigAnalyticsAdapter';

describe('statsigAnalyticsAdapter helpers', () => {
    describe('toStatsigCustomTraits', () => {
        it('drops null and undefined values from user traits', () => {
            expect(
                toStatsigCustomTraits({
                    email: 'user@example.com',
                    name: null,
                    platform: 'web',
                    plan: undefined,
                    count: 3,
                    active: true,
                }),
            ).toEqual({
                email: 'user@example.com',
                platform: 'web',
                count: 3,
                active: true,
            });
        });
    });

    describe('toStatsigEventMetadata', () => {
        it('converts analytics properties to Statsig string metadata', () => {
            expect(
                toStatsigEventMetadata({
                    id: 'download_ios',
                    count: 2,
                    enabled: false,
                    missing: null,
                    unset: undefined,
                }),
            ).toEqual({
                id: 'download_ios',
                count: '2',
                enabled: 'false',
            });
        });
    });
});