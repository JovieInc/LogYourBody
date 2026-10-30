export function isVaultAssetUrl(value: string, origins: readonly string[]): boolean {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (!origins.includes(url.origin)) return false;
  if (url.protocol === 'https:') return true;
  return url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1');
}
