import { z } from 'zod'

const serverEnvSchema = z.object({
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(),
  OPENAI_API_KEY: z.string().min(1).optional(),
  CLERK_WEBHOOK_SECRET: z.string().min(1).optional(),
  DEBUG_SECRET: z.string().optional(),
  DATABASE_URL: z.string().optional(),
  POSTGRES_URL: z.string().optional(),
  BUILD_TARGET: z.string().optional(),
  VERCEL_ENV: z.string().optional(),
})

type ServerEnv = z.infer<typeof serverEnvSchema>

let cachedServerEnv: Readonly<ServerEnv> | null = null

function buildRawServerEnv() {
  return {
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    CLERK_WEBHOOK_SECRET: process.env.CLERK_WEBHOOK_SECRET,
    DEBUG_SECRET: process.env.DEBUG_SECRET,
    DATABASE_URL: process.env.DATABASE_URL,
    POSTGRES_URL: process.env.POSTGRES_URL,
    BUILD_TARGET: process.env.BUILD_TARGET,
    VERCEL_ENV: process.env.VERCEL_ENV,
  }
}

export function getServerEnv(): Readonly<ServerEnv> {
  if (cachedServerEnv) {
    return cachedServerEnv
  }

  const result = serverEnvSchema.safeParse(buildRawServerEnv())

  if (!result.success) {
    console.error('[env] Invalid server environment variables', result.error.flatten().fieldErrors)
    throw new Error('Invalid server environment variables')
  }

  cachedServerEnv = Object.freeze(result.data)
  return cachedServerEnv
}

export const serverEnv = getServerEnv()

export type { ServerEnv }
