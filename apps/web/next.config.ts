import type { NextConfig } from 'next';
import bundleAnalyzer from '@next/bundle-analyzer';
import { withSentryConfig } from '@sentry/nextjs';
import { version } from './package.json';
import { logYourBody } from '@jovieinc/product-registry';
import { cspReportOnlyDirectives } from './src/lib/generated/csp.generated';

// Bundle analyzer configuration
const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === 'true',
});

const nextConfig: NextConfig = {
  transpilePackages: ['@jovie/ui'],
  // Enable static export for Capacitor when needed
  output: process.env.BUILD_TARGET === 'capacitor' ? 'export' : undefined,

  // Disable image optimization for Capacitor builds
  images: {
    unoptimized: process.env.BUILD_TARGET === 'capacitor',
    localPatterns: [
      { pathname: '/brand/**' },
      { pathname: '/marketing/**' },
      { pathname: '/product-screenshots/**' },
    ],
  },

  // Add trailing slash for better Capacitor compatibility
  trailingSlash: false,

  // Use relative paths for Capacitor
  assetPrefix: process.env.BUILD_TARGET === 'capacitor' ? './' : undefined,

  // Modularize imports to reduce bundle size
  modularizeImports: {
    'lucide-react': {
      transform: 'lucide-react/dist/esm/icons/{{kebabCase member}}',
    },
  },

  // Experimental features
  experimental: {
    optimizePackageImports: ['lucide-react', 'date-fns', '@radix-ui/react-icons'],
    serverActions: {
      bodySizeLimit: '2mb',
    },
  },

  // Server external packages
  serverExternalPackages: ['pdf-parse', '@statsig/statsig-node-core'],

  // Don't skip TypeScript checks
  typescript: {
    ignoreBuildErrors: false,
  },

  // Environment variables
  env: {
    NEXT_PUBLIC_APP_VERSION: version,
    // Release identity for Sentry events and sourcemap upload: the deployed commit.
    NEXT_PUBLIC_SENTRY_RELEASE:
      process.env.NEXT_PUBLIC_SENTRY_RELEASE ||
      process.env.VERCEL_GIT_COMMIT_SHA ||
      version,
    // Lets browser analytics derive its tier from the Vercel environment.
    NEXT_PUBLIC_VERCEL_ENV: process.env.VERCEL_ENV ?? '',
  },

  async redirects() {
    return [
      {
        // The Vercel domain redirect answers the apex with 307 before this app
        // runs. When a request does reach Next, send that host to www with 308.
        // Dots are escaped because `has` host values are regexes.
        source: '/:path*',
        has: [{ type: 'host', value: logYourBody.identity.domain.replace(/\./g, '\\.') }],
        destination: `${logYourBody.links.home}/:path*`,
        permanent: true,
      },
    ];
  },

  // RFC 9728 protected-resource metadata for the MCP server (see src/lib/mcp/contract.ts).
  async rewrites() {
    return {
      afterFiles: [
        {
          source: '/.well-known/oauth-protected-resource/api/mcp',
          destination: '/api/mcp/oauth-protected-resource',
        },
        {
          source: '/.well-known/oauth-protected-resource',
          destination: '/api/mcp/oauth-protected-resource',
        },
      ],
      // Only after real files/pages/dynamic routes; ordinary HTML404 is untouched.
      fallback: [
        {
          // Keep the same path exclusions as middleware so a skipped request
          // cannot forge its gate-decision header.
          source:
            '/:path((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
          has: [{ type: 'header', key: 'x-lyb-public-markdown', value: '1' }],
          destination: '/api/marketing/markdown-not-found',
        },
      ],
    };
  },

  // Headers for apple-app-site-association
  async headers() {
    return [
      {
        source: '/.well-known/apple-app-site-association',
        headers: [
          {
            key: 'Content-Type',
            value: 'application/json',
          },
        ],
      },
      {
        source: '/apple-app-site-association',
        headers: [
          {
            key: 'Content-Type',
            value: 'application/json',
          },
        ],
      },
      {
        // Report-only CSP: violations are collected at /api/csp-report without
        // blocking anything. The generated module has no report-uri directive,
        // so the collector endpoint is appended here.
        source: '/:path*',
        headers: [
          {
            key: 'Content-Security-Policy-Report-Only',
            value: `${cspReportOnlyDirectives}; report-uri /api/csp-report; report-to csp-endpoint`,
          },
          {
            key: 'Reporting-Endpoints',
            value: 'csp-endpoint="/api/csp-report"',
          },
        ],
      },
    ];
  },

  // Webpack configuration (only used when not using Turbopack)
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        path: false,
        crypto: false,
      };
    }
    return config;
  },
};

const configWithAnalyzer = withBundleAnalyzer(nextConfig);

// Sourcemaps are uploaded to Sentry only when the build has upload credentials
// (Vercel build env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT). Without them
// the runtime SDK still reports, just with minified frames.
const shouldUploadSourcemaps = Boolean(
  process.env.SENTRY_AUTH_TOKEN &&
    process.env.SENTRY_ORG &&
    process.env.SENTRY_PROJECT
);

export default shouldUploadSourcemaps
  ? withSentryConfig(configWithAnalyzer, {
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
      silent: true,
      release: { name: process.env.NEXT_PUBLIC_SENTRY_RELEASE },
      sourcemaps: { deleteSourcemapsAfterUpload: true },
      telemetry: false,
    })
  : configWithAnalyzer;
