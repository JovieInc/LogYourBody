#!/usr/bin/env node

/**
 * Build script for Web platform
 * Generates CSS variables and JS/TS exports from design tokens
 */

import StyleDictionary from 'style-dictionary';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import config from '../config/style-dictionary.web.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

console.log('🌐 Building design tokens for Web (Tailwind CSS)...\n');

// Build web tokens
const sd = new StyleDictionary(config);
await sd.buildAllPlatforms();

console.log('\n✅ Web design tokens built successfully!');
console.log(`📦 Output: ${resolve(__dirname, '../build/web/')}\n`);
console.log('💡 Next steps:');
console.log('  1. Import tokens.css in your app');
console.log('  2. Configure Tailwind to use CSS variables');
console.log('  3. Use tokens.js for JavaScript access\n');
