const nextJest = require('next/jest')

const createJestConfig = nextJest({
  dir: './',
})

// Node test configuration for API routes
const nodeJestConfig = {
  testEnvironment: 'node',
  moduleNameMapper: {
    '^@/env-server$': '<rootDir>/src/env-server',
    '^@/env$': '<rootDir>/src/env',
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  testMatch: [
    '<rootDir>/src/**/*.node.test.{js,jsx,ts,tsx}',
  ],
  testPathIgnorePatterns: [
    '/node_modules/',
    '/legacy-react/',
    '/.next/',
    '/dist/',
  ],
}

module.exports = createJestConfig(nodeJestConfig)