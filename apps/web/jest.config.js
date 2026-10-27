const nextJest = require('next/jest');

const createJestConfig = nextJest({
  // Provide the path to your Next.js app to load next.config.js and .env files in your test environment
  dir: './',
});

// Add any custom config to be passed to Jest
const customJestConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  testEnvironment: 'jest-environment-jsdom',
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^lucide-react(.*)$': '<rootDir>/tests/mocks/lucide-react.js',
  },
  testMatch: [
    '<rootDir>/src/**/__tests__/**/*.{js,jsx,ts,tsx}',
    '<rootDir>/src/**/*.{spec,test}.{js,jsx,ts,tsx}',
  ],
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.{js,jsx,ts,tsx}',
    '!src/**/__tests__/**',
  ],
  coverageReporters: ['json', 'lcov', 'text', 'clover', 'json-summary'],
  // Whole-web nonregression floor measured across 141 suites / 1,409 tests.
  // Retain the source denominator above; raise only with complete-suite evidence.
  coverageThreshold: {
    global: {
      statements: 54.4,
      branches: 56.1,
      functions: 56.7,
      lines: 55.9,
    },
  },
  testPathIgnorePatterns: ['/node_modules/', '/legacy-react/', '/.next/', '/dist/'],
  modulePathIgnorePatterns: ['/legacy-react/'],
};

// createJestConfig is exported this way to ensure that next/jest can load the Next.js config which is async
module.exports = createJestConfig(customJestConfig);
