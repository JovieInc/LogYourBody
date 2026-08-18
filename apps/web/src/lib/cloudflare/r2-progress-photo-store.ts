import { createHash } from 'node:crypto';
import { authorizeS3Request, canonicalQueryString, presignS3Request, uriEncode } from './r2-aws-v4';

export const PROGRESS_PHOTO_MAX_BYTES = 10 * 1024 * 1024;
export const PROGRESS_PHOTO_UPLOAD_TTL_SECONDS = 300;
export const PROGRESS_PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

export type ProgressPhotoContentType = (typeof PROGRESS_PHOTO_CONTENT_TYPES)[number];

export type R2PhotoStoreConfig = {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
  publicBaseUrl: string;
  apiHost: string;
};

export type ProgressPhotoUploadTicket = {
  uploadUrl: string;
  uploadMethod: 'PUT';
  uploadHeaders: Record<string, string>;
  objectKey: string;
  photoUrl: string;
  storagePath: string;
  expiresIn: number;
};

const CONTENT_TYPE_EXTENSION: Record<ProgressPhotoContentType, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export function readR2PhotoStoreConfig(
  env: NodeJS.ProcessEnv = process.env,
): R2PhotoStoreConfig | null {
  const accountId = env.CLOUDFLARE_ACCOUNT_ID?.trim();
  const accessKeyId = env.CLOUDFLARE_R2_ACCESS_KEY_ID?.trim();
  const secretAccessKey = env.CLOUDFLARE_R2_SECRET_ACCESS_KEY?.trim();
  const bucket = env.CLOUDFLARE_R2_BUCKET?.trim();
  const publicBaseUrl = parsePublicBaseUrl(env.CLOUDFLARE_R2_PUBLIC_BASE_URL);
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return null;
  }
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(accountId)) return null;
  if (!/^[A-Za-z0-9._-]{3,63}$/.test(bucket)) return null;
  return {
    accountId,
    accessKeyId,
    secretAccessKey,
    bucket,
    publicBaseUrl,
    apiHost: `${accountId}.r2.cloudflarestorage.com`,
  };
}

export function parsePublicBaseUrl(value: string | undefined): string | null {
  if (!value?.trim()) return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== 'https:') return null;
    if (!url.hostname) return null;
    if (url.search || url.hash) return null;
    const path = url.pathname.replace(/\/+$/, '');
    return `${url.origin}${path === '/' ? '' : path}`;
  } catch {
    return null;
  }
}

export function isProgressPhotoContentType(value: string): value is ProgressPhotoContentType {
  return (PROGRESS_PHOTO_CONTENT_TYPES as readonly string[]).includes(value);
}

export function progressPhotoOwnerPrefix(userId: string): string {
  return `progress-photos/${safeOwnerSegment(userId)}/`;
}

export function progressPhotoObjectKey(input: {
  userId: string;
  metricsId: string;
  contentType: ProgressPhotoContentType;
  now?: Date;
}): string {
  const metricsId = input.metricsId.trim();
  if (!/^[A-Za-z0-9_-]{8,80}$/.test(metricsId)) {
    throw new Error('invalid_metrics_id');
  }
  const stamp = (input.now ?? new Date()).getTime();
  const extension = CONTENT_TYPE_EXTENSION[input.contentType];
  return `${progressPhotoOwnerPrefix(input.userId)}${metricsId}_${stamp}.${extension}`;
}

export function publicProgressPhotoUrl(config: R2PhotoStoreConfig, objectKey: string): string {
  const encodedKey = objectKey
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
  return `${config.publicBaseUrl}/${encodedKey}`;
}

export function createProgressPhotoUploadTicket(input: {
  config: R2PhotoStoreConfig;
  userId: string;
  metricsId: string;
  contentType: ProgressPhotoContentType;
  now?: Date;
  expiresIn?: number;
}): ProgressPhotoUploadTicket {
  const now = input.now ?? new Date();
  const expiresIn = input.expiresIn ?? PROGRESS_PHOTO_UPLOAD_TTL_SECONDS;
  const objectKey = progressPhotoObjectKey({
    userId: input.userId,
    metricsId: input.metricsId,
    contentType: input.contentType,
    now,
  });
  const canonicalUri = `/${uriEncode(input.config.bucket, false)}/${uriEncode(objectKey, false)}`;
  const signed = presignS3Request({
    method: 'PUT',
    host: input.config.apiHost,
    canonicalUri,
    accessKeyId: input.config.accessKeyId,
    secretAccessKey: input.config.secretAccessKey,
    headers: { 'content-type': input.contentType },
    expiresIn,
    now,
  });
  return {
    uploadUrl: signed.url,
    uploadMethod: 'PUT',
    uploadHeaders: signed.signedHeaders,
    objectKey,
    photoUrl: publicProgressPhotoUrl(input.config, objectKey),
    storagePath: objectKey,
    expiresIn,
  };
}

export async function deleteOwnedProgressPhotos(
  userId: string,
  options: {
    env?: NodeJS.ProcessEnv;
    fetcher?: typeof fetch;
    now?: Date;
  } = {},
): Promise<void> {
  const config = readR2PhotoStoreConfig(options.env ?? process.env);
  if (!config) return;
  const fetcher = options.fetcher ?? fetch;
  const now = options.now ?? new Date();
  const prefix = progressPhotoOwnerPrefix(userId);
  let continuationToken: string | undefined;
  do {
    const listed = await listR2Objects({
      config,
      prefix,
      continuationToken,
      fetcher,
      now,
    });
    for (const key of listed.keys) {
      if (!key.startsWith(prefix)) {
        throw new Error('r2_list_returned_unowned_object');
      }
      await deleteR2Object({ config, key, fetcher, now });
    }
    continuationToken = listed.nextContinuationToken;
  } while (continuationToken);
}

function safeOwnerSegment(userId: string): string {
  const trimmed = userId.trim();
  if (!trimmed) throw new Error('invalid_user_id');
  if (/^[A-Za-z0-9._:-]{1,128}$/.test(trimmed)) return trimmed;
  return createHash('sha256').update(trimmed).digest('hex');
}

function objectPath(bucket: string, key?: string): string {
  const suffix = key ? `/${uriEncode(key, false)}` : '';
  return `/${uriEncode(bucket, false)}${suffix}`;
}

async function listR2Objects(input: {
  config: R2PhotoStoreConfig;
  prefix: string;
  continuationToken?: string;
  fetcher: typeof fetch;
  now: Date;
}): Promise<{ keys: string[]; nextContinuationToken?: string }> {
  const query: Record<string, string> = {
    'list-type': '2',
    prefix: input.prefix,
  };
  if (input.continuationToken) query['continuation-token'] = input.continuationToken;
  const canonicalUri = objectPath(input.config.bucket);
  const headers = authorizeS3Request({
    method: 'GET',
    host: input.config.apiHost,
    canonicalUri,
    query,
    accessKeyId: input.config.accessKeyId,
    secretAccessKey: input.config.secretAccessKey,
    payload: '',
    now: input.now,
  });
  const url = `https://${input.config.apiHost}${canonicalUri}?${canonicalQueryString(query)}`;
  const response = await input.fetcher(url, { method: 'GET', headers, cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`r2_list_failed_${response.status}`);
  }
  const xml = await response.text();
  const keys = [...xml.matchAll(/<Key>([^<]+)<\/Key>/g)].map((match) => decodeXml(match[1] ?? ''));
  const truncated = /<IsTruncated>\s*true\s*<\/IsTruncated>/i.test(xml);
  const next = xml.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/)?.[1];
  return {
    keys,
    nextContinuationToken: truncated ? decodeXml(next ?? '') || undefined : undefined,
  };
}

async function deleteR2Object(input: {
  config: R2PhotoStoreConfig;
  key: string;
  fetcher: typeof fetch;
  now: Date;
}): Promise<void> {
  const canonicalUri = objectPath(input.config.bucket, input.key);
  const headers = authorizeS3Request({
    method: 'DELETE',
    host: input.config.apiHost,
    canonicalUri,
    accessKeyId: input.config.accessKeyId,
    secretAccessKey: input.config.secretAccessKey,
    payload: '',
    now: input.now,
  });
  const response = await input.fetcher(`https://${input.config.apiHost}${canonicalUri}`, {
    method: 'DELETE',
    headers,
    cache: 'no-store',
  });
  if (!response.ok && response.status !== 404) {
    throw new Error(`r2_delete_failed_${response.status}`);
  }
}

function decodeXml(value: string): string {
  return value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
}

// Touch the canonical env names so the env-surface guard can see them.
void process.env.CLOUDFLARE_ACCOUNT_ID;
void process.env.CLOUDFLARE_R2_ACCESS_KEY_ID;
void process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY;
void process.env.CLOUDFLARE_R2_BUCKET;
void process.env.CLOUDFLARE_R2_PUBLIC_BASE_URL;
