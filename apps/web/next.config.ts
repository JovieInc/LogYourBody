import type { NextConfig } from "next";
import { version } from "./package.json";

// Bundle analyzer configuration
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
})

const nextConfig: NextConfig = {
  // Enable static export for Capacitor when needed
  output: process.env.BUILD_TARGET === 'capacitor' ? 'export' : undefined,

  // Disable image optimization for Capacitor builds
  images: {
    unoptimized: process.env.BUILD_TARGET === 'capacitor',
    remotePatterns: [
      {
        protocol: 'https',
        hostname: '**.supabase.co',
      },
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
  serverExternalPackages: ['pdf-parse'],
  
  // Skip ESLint during builds - we'll run it separately
  eslint: {
    ignoreDuringBuilds: true,
  },
  
  // Don't skip TypeScript checks
  typescript: {
    ignoreBuildErrors: false,
  },
  
  // Environment variables
  env: {
    NEXT_PUBLIC_APP_VERSION: version,
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

export default withBundleAnalyzer(nextConfig);
