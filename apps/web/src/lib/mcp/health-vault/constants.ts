import { endpoints } from '../../generated/endpoints.generated';

export const HEALTH_VAULT_VIEW_TTL_MS = 5 * 60 * 1000;
export const HEALTH_VAULT_WIDGET_URI = 'ui://logyourbody/health-vault.html';
export const HEALTH_VAULT_WIDGET_DOMAIN = 'https://web-sandbox.oaiusercontent.com';
export const HEALTH_VAULT_API_ORIGIN = endpoints.hosts.api.url;
export const HEALTH_VAULT_PHOTO_ORIGIN = `https://${endpoints.vendor.cloudflare.r2PublicHost}`;

/** Widget-capable MCP clients. Grok, Muse, and Claude get the share tool only. */
const WIDGET_CLIENT_IDS = new Set(['chatgpt']);

export function isHealthVaultWidgetSurface(clientId: string | null | undefined): boolean {
  return typeof clientId === 'string' && WIDGET_CLIENT_IDS.has(clientId);
}

export function vaultConnectOrigins(apiOrigin: string): string[] {
  const origins = [HEALTH_VAULT_API_ORIGIN, HEALTH_VAULT_PHOTO_ORIGIN];
  if (apiOrigin && !origins.includes(apiOrigin)) origins.push(apiOrigin);
  return origins;
}

export const HEALTH_VAULT_MODEL_INSTRUCTIONS =
  'Measurements from scans, photos, and weigh-ins are not in tool results. share_summary_with_chatgpt returns a summary only after the user confirms those fields. Do not invent measurements.';

export function healthVaultResourceMeta(apiOrigin: string): Record<string, unknown> {
  const connect = vaultConnectOrigins(apiOrigin);
  return {
    ui: {
      prefersBorder: true,
      domain: HEALTH_VAULT_WIDGET_DOMAIN,
      csp: {
        connectDomains: connect,
        resourceDomains: connect,
      },
    },
    'openai/widgetDescription':
      'LogYourBody vault view. Tool results list counts only. Measurements stay in this view.',
    'openai/widgetCSP': {
      connect_domains: connect,
      resource_domains: connect,
    },
    'openai/widgetDomain': HEALTH_VAULT_WIDGET_DOMAIN,
  };
}
