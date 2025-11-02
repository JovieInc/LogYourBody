/**
 * Style Dictionary Configuration for Web (Tailwind CSS)
 * Generates CSS variables and JavaScript/TypeScript exports
 */

export default {
  source: [
    'tokens/core/**/*.json',
    'tokens/semantic/**/*.json',
    'tokens/platform/web.json'
  ],
  platforms: {
    css: {
      transformGroup: 'css',
      buildPath: 'build/web/',
      files: [
        {
          destination: 'tokens.css',
          format: 'css/variables',
          options: {
            selector: ':root',
            outputReferences: true
          }
        }
      ]
    },
    js: {
      transformGroup: 'js',
      buildPath: 'build/web/',
      files: [
        {
          destination: 'tokens.js',
          format: 'javascript/es6',
          options: {
            outputReferences: true
          }
        },
        {
          destination: 'tokens.d.ts',
          format: 'typescript/es6-declarations',
          options: {
            outputStringLiterals: true
          }
        },
        {
          destination: 'tokens.json',
          format: 'json/nested'
        }
      ]
    },
    scss: {
      transformGroup: 'scss',
      buildPath: 'build/web/',
      files: [
        {
          destination: 'tokens.scss',
          format: 'scss/variables',
          options: {
            outputReferences: true
          }
        }
      ]
    }
  }
};
