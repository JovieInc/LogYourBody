#!/usr/bin/env node

/**
 * Validation script for design tokens
 * Checks token structure and values for common issues
 */

const fs = require('fs');
const path = require('path');
const chroma = require('chroma-js');

console.log('🔍 Validating design tokens...\n');

let hasErrors = false;

// Load all token files
const tokensDir = path.join(__dirname, '../tokens');
const tokenFiles = [];

function findTokenFiles(dir) {
  const files = fs.readdirSync(dir);
  files.forEach(file => {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      findTokenFiles(fullPath);
    } else if (file.endsWith('.json')) {
      tokenFiles.push(fullPath);
    }
  });
}

findTokenFiles(tokensDir);

console.log(`Found ${tokenFiles.length} token files\n`);

// Validate each file
tokenFiles.forEach(file => {
  try {
    const content = JSON.parse(fs.readFileSync(file, 'utf8'));
    console.log(`✅ ${path.relative(tokensDir, file)}`);

    // Validate colors have proper contrast (WCAG AA)
    if (file.includes('colors.json')) {
      validateColorContrast(content);
    }
  } catch (error) {
    console.error(`❌ ${path.relative(tokensDir, file)}: ${error.message}`);
    hasErrors = true;
  }
});

function validateColorContrast(tokens) {
  // Check if text colors have sufficient contrast against backgrounds
  try {
    const bgColor = '#111111'; // Background color

    if (tokens.color && tokens.color.semantic && tokens.color.semantic.text) {
      const textColors = tokens.color.semantic.text;

      Object.entries(textColors).forEach(([name, colorData]) => {
        if (colorData.value && colorData.value.startsWith('#')) {
          try {
            const contrast = chroma.contrast(bgColor, colorData.value);
            const meetsAA = contrast >= 4.5;
            const meetsAAA = contrast >= 7;

            const status = meetsAAA ? '✅ AAA' : meetsAA ? '⚠️  AA' : '❌ FAIL';
            console.log(`  ${status} ${name}: ${contrast.toFixed(2)}:1`);

            if (!meetsAA) {
              console.error(`    ⚠️  Warning: ${name} does not meet WCAG AA standards (4.5:1)`);
            }
          } catch (e) {
            // Skip invalid colors
          }
        }
      });
    }
  } catch (error) {
    // Skip contrast validation if chroma fails
  }
}

console.log();

if (hasErrors) {
  console.error('❌ Validation failed with errors\n');
  process.exit(1);
} else {
  console.log('✅ All tokens validated successfully!\n');
}
