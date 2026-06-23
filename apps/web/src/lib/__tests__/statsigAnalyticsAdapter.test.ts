const mockUpdateUserAsync = jest.fn().mockResolvedValue(undefined);
const mockLogEvent = jest.fn();
const mockInitializeAsync = jest.fn().mockResolvedValue(undefined);
const mockCheckGate = jest.fn().mockReturnValue(false);

jest.mock('@statsig/js-client', () => ({
    StatsigClient: jest.fn().mockImplementation(() => ({
        initializeAsync: mockInitializeAsync,
        updateUserAsync: mockUpdateUserAsync,
        logEvent: mockLogEvent,
        checkGate: mockCheckGate,
    })),
}));

import { createStatsigAnalytics } from '../statsigAnalyticsAdapter';

describe('createStatsigAnalytics', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('filters null traits before updating the Statsig user', () => {
        const analytics = createStatsigAnalytics({ clientKey: 'test-key' });

        analytics.identify('user-1', {
            email: 'user@example.com',
            plan: null,
            active: true,
        });

        expect(mockUpdateUserAsync).toHaveBeenCalledWith({
            userID: 'user-1',
            custom: {
                email: 'user@example.com',
                active: true,
            },
        });
    });

    it('converts event metadata to strings and drops null values', () => {
        const analytics = createStatsigAnalytics({ clientKey: 'test-key' });

        analytics.track('app_open', {
            source: 'landing',
            count: 3,
            enabled: true,
            missing: null,
        });

        expect(mockLogEvent).toHaveBeenCalledWith({
            eventName: 'app_open',
            metadata: {
                source: 'landing',
                count: '3',
                enabled: 'true',
            },
        });
    });
});