const { spawnSync } = require('node:child_process')

const isVercel = process.env.VERCEL === '1'

// Local hooks and GitHub Actions prerender public routes that import Supabase.
// Vercel deployments must use their real configured project environment.
if (!isVercel) {
  process.env.NEXT_PUBLIC_SUPABASE_URL ||= 'https://example.supabase.co'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||= 'fake-anon-key'
}

const result = spawnSync('next', ['build'], {
  stdio: 'inherit',
  shell: process.platform === 'win32',
})

process.exit(result.status ?? 1)
