export const logYourBodyIntegrations = [
  {
    id: 'apple_health',
    label: 'Apple Health',
    description: 'Weight, body fat, and steps.',
    authorization: 'native_permission',
    accountScope: 'device',
    platforms: ['ios'],
    marketing: true,
    capabilities: [
      {
        id: 'read_body_metrics',
        label: 'Sync supported body metrics and steps',
        mode: 'read',
        requiredScopes: [
          'HKQuantityTypeIdentifierBodyMass',
          'HKQuantityTypeIdentifierBodyFatPercentage',
          'HKQuantityTypeIdentifierStepCount',
        ],
        requiresApproval: false,
        availability: 'available',
      },
    ],
  },
  {
    id: 'bodyspec',
    label: 'BodySpec',
    description: 'DEXA scans',
    authorization: 'oauth',
    accountScope: 'device',
    platforms: ['ios'],
    // Adapter exists; production OAuth configuration/MCP delivery are not certified.
    marketing: false,
    capabilities: [
      {
        id: 'import_dexa_scans',
        label: 'Import DEXA scans',
        mode: 'read',
        requiredScopes: ['openid', 'profile', 'email'],
        requiresApproval: false,
        availability: 'available',
      },
    ],
  },
];
