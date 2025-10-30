#!/usr/bin/env node

/**
 * Build script for all platforms
 * Runs iOS and Web builds
 */

const { execSync } = require('child_process');

console.log('🚀 Building design tokens for all platforms...\n');

try {
  console.log('Building iOS tokens...');
  execSync('node scripts/build-ios.js', { stdio: 'inherit' });

  console.log('\nBuilding Web tokens...');
  execSync('node scripts/build-web.js', { stdio: 'inherit' });

  console.log('\n✅ All platforms built successfully!\n');
} catch (error) {
  console.error('❌ Build failed:', error.message);
  process.exit(1);
}
