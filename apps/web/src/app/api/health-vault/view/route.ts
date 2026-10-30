import { healthVaultHttp } from '../dependencies';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export const POST = healthVaultHttp.view;
export const OPTIONS = healthVaultHttp.options;
