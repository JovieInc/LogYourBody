import { z } from 'zod'

const nodeEnvSchema = z.enum(['development', 'test', 'production'])

const publicEnvSchema = z.object({
  NODE_ENV: nodeEnvSchema.default('development'),
  NEXT_PUBLIC_SUPABASE_URL: z
    .string()
    .url({ message: 'NEXT_PUBLIC_SUPABASE_URL must be a valid URL' })
    .default('http://localhost:54321'),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z
    .string()
    .min(1, { message: 'NEXT_PUBLIC_SUPABASE_ANON_KEY is required' })
    .default('development-anon-key'),
  NEXT_PUBLIC_API_URL: z
    .string()
    .url({ message: 'NEXT_PUBLIC_API_URL must be a valid URL' })
    .optional(),
  NEXT_PUBLIC_WS_URL: z
    .string()
    .url({ message: 'NEXT_PUBLIC_WS_URL must be a valid URL' })
    .optional(),
  NEXT_PUBLIC_GA_ID: z.string().optional(),
  NEXT_PUBLIC_MIXPANEL_TOKEN: z.string().optional(),
  NEXT_PUBLIC_VERSION: z.string().optional(),
  NEXT_PUBLIC_APP_VERSION: z.string().optional(),
  NEXT_PUBLIC_VERCEL_ENV: z.string().optional(),
  NEXT_PUBLIC_SITE_URL: z
    .string()
    .url({ message: 'NEXT_PUBLIC_SITE_URL must be a valid URL' })
    .optional(),
  VERCEL_ENV: z.string().optional(),
})

type PublicEnv = z.infer<typeof publicEnvSchema>

const FALLBACK_KEYS: Array<keyof PublicEnv> = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_ANON_KEY',
]

let cachedPublicEnv: Readonly<PublicEnv> | null = null

function buildRawPublicEnv() {
  return {
    NODE_ENV: process.env.NODE_ENV,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
    NEXT_PUBLIC_WS_URL: process.env.NEXT_PUBLIC_WS_URL,
    NEXT_PUBLIC_GA_ID: process.env.NEXT_PUBLIC_GA_ID,
    NEXT_PUBLIC_MIXPANEL_TOKEN: process.env.NEXT_PUBLIC_MIXPANEL_TOKEN,
    NEXT_PUBLIC_VERSION: process.env.NEXT_PUBLIC_VERSION,
    NEXT_PUBLIC_APP_VERSION: process.env.NEXT_PUBLIC_APP_VERSION,
    NEXT_PUBLIC_VERCEL_ENV: process.env.NEXT_PUBLIC_VERCEL_ENV,
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL,
    VERCEL_ENV: process.env.VERCEL_ENV,
  }
}

function logFallbackWarnings() {
  if (process.env.NODE_ENV === 'production') {
    return
  }

  const missing = FALLBACK_KEYS.filter((key) => !process.env[key])
  if (missing.length === 0) {
    return
  }

  const formatted = missing.join(', ')
  console.warn(
    `[env] Using development fallbacks for missing public environment variables: ${formatted}`
  )
}

export function getPublicEnv(): Readonly<PublicEnv> {
  if (cachedPublicEnv) {
    return cachedPublicEnv
  }

  const result = publicEnvSchema.safeParse(buildRawPublicEnv())

  if (!result.success) {
    console.error('[env] Invalid public environment variables', result.error.flatten().fieldErrors)
    throw new Error('Invalid public environment variables')
  }

  logFallbackWarnings()

  cachedPublicEnv = Object.freeze(result.data)
  return cachedPublicEnv
}

export const publicEnv = getPublicEnv()

export type { PublicEnv }

export function __resetPublicEnvForTesting() {
  if (process.env.NODE_ENV === 'test') {
    cachedPublicEnv = null
  }
}
