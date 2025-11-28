const path = require('path');
const { defineConfig } = require('vitest/config');

module.exports = defineConfig({
  resolve: {
    alias: {
      '@shared-lib': path.resolve(__dirname, '../shared-lib/src'),
      '@shared-lib/*': path.resolve(__dirname, '../shared-lib/src/*'),
      '@shared-ui': path.resolve(__dirname, './src'),
      react: path.resolve(__dirname, '../../node_modules/react'),
      'react-dom': path.resolve(__dirname, '../../node_modules/react-dom'),
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './vitest.setup.ts',
    exclude: ['dist/**', 'node_modules/**'],
  },
});
