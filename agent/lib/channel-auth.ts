import { localDev, placeholderAuth } from 'eve/channels/auth';

type EveAuthEnvironment = Pick<NodeJS.ProcessEnv, 'LYB_EVE_ALLOW_LOCAL_DEV' | 'VERCEL_ENV'>;

export function eveRouteAuth(environment: EveAuthEnvironment = process.env) {
  const allowLocalDev =
    environment.LYB_EVE_ALLOW_LOCAL_DEV === '1' && environment.VERCEL_ENV !== 'production';

  return allowLocalDev ? [localDev(), placeholderAuth()] : [placeholderAuth()];
}
