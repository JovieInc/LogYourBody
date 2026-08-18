import { createHash, createHmac } from 'node:crypto';

export const R2_SIGNING_REGION = 'auto';
export const R2_SIGNING_SERVICE = 's3';
export const UNSIGNED_PAYLOAD = 'UNSIGNED-PAYLOAD';

export function sha256Hex(data: string | Buffer): string {
  return createHash('sha256').update(data).digest('hex');
}

export function hmacSha256(key: Buffer | string, data: string): Buffer {
  return createHmac('sha256', key).update(data, 'utf8').digest();
}

export function uriEncode(value: string, encodeSlash = true): string {
  let encoded = '';
  for (const character of value) {
    if (/[A-Za-z0-9._~-]/.test(character)) {
      encoded += character;
      continue;
    }
    if (character === '/' && !encodeSlash) {
      encoded += '/';
      continue;
    }
    const bytes = Buffer.from(character, 'utf8');
    for (const byte of bytes) {
      encoded += `%${byte.toString(16).toUpperCase().padStart(2, '0')}`;
    }
  }
  return encoded;
}

export function formatAmzDate(now: Date): { amzDate: string; dateStamp: string } {
  const iso = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const amzDate = `${iso.slice(0, 15)}Z`;
  return { amzDate, dateStamp: amzDate.slice(0, 8) };
}

export function canonicalQueryString(params: Record<string, string>): string {
  return Object.keys(params)
    .sort()
    .map((key) => `${uriEncode(key)}=${uriEncode(params[key] ?? '')}`)
    .join('&');
}

export function canonicalHeaders(headers: Record<string, string>): {
  canonical: string;
  signedHeaders: string;
} {
  const normalized = Object.entries(headers).map(([name, value]) => ({
    name: name.toLowerCase(),
    value: value.trim().replace(/\s+/g, ' '),
  }));
  normalized.sort((left, right) => left.name.localeCompare(right.name));
  const signedHeaders = normalized.map((header) => header.name).join(';');
  const canonical = `${normalized.map((header) => `${header.name}:${header.value}`).join('\n')}\n`;
  return { canonical, signedHeaders };
}

export function credentialScope(dateStamp: string): string {
  return `${dateStamp}/${R2_SIGNING_REGION}/${R2_SIGNING_SERVICE}/aws4_request`;
}

export function signingKey(secretAccessKey: string, dateStamp: string): Buffer {
  const dateKey = hmacSha256(`AWS4${secretAccessKey}`, dateStamp);
  const regionKey = hmacSha256(dateKey, R2_SIGNING_REGION);
  const serviceKey = hmacSha256(regionKey, R2_SIGNING_SERVICE);
  return hmacSha256(serviceKey, 'aws4_request');
}

export function buildCanonicalRequest(input: {
  method: string;
  canonicalUri: string;
  query: Record<string, string>;
  headers: Record<string, string>;
  payloadHash: string;
}): { canonicalRequest: string; signedHeaders: string } {
  const { canonical, signedHeaders } = canonicalHeaders(input.headers);
  const canonicalRequest = [
    input.method.toUpperCase(),
    input.canonicalUri,
    canonicalQueryString(input.query),
    canonical,
    signedHeaders,
    input.payloadHash,
  ].join('\n');
  return { canonicalRequest, signedHeaders };
}

export function stringToSign(amzDate: string, dateStamp: string, canonicalRequest: string): string {
  return [
    'AWS4-HMAC-SHA256',
    amzDate,
    credentialScope(dateStamp),
    sha256Hex(canonicalRequest),
  ].join('\n');
}

export function signatureFor(input: {
  secretAccessKey: string;
  dateStamp: string;
  stringToSign: string;
}): string {
  return hmacSha256(
    signingKey(input.secretAccessKey, input.dateStamp),
    input.stringToSign,
  ).toString('hex');
}

export function presignS3Request(input: {
  method: string;
  host: string;
  canonicalUri: string;
  accessKeyId: string;
  secretAccessKey: string;
  headers: Record<string, string>;
  expiresIn: number;
  now: Date;
}): { url: string; signedHeaders: Record<string, string> } {
  const { amzDate, dateStamp } = formatAmzDate(input.now);
  const query = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': `${input.accessKeyId}/${credentialScope(dateStamp)}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(input.expiresIn),
    'X-Amz-SignedHeaders': '',
  };
  const headers = { ...input.headers, host: input.host };
  const { signedHeaders } = canonicalHeaders(headers);
  query['X-Amz-SignedHeaders'] = signedHeaders;
  const { canonicalRequest } = buildCanonicalRequest({
    method: input.method,
    canonicalUri: input.canonicalUri,
    query,
    headers,
    payloadHash: UNSIGNED_PAYLOAD,
  });
  const signed = signatureFor({
    secretAccessKey: input.secretAccessKey,
    dateStamp,
    stringToSign: stringToSign(amzDate, dateStamp, canonicalRequest),
  });
  const url = `https://${input.host}${input.canonicalUri}?${canonicalQueryString({
    ...query,
    'X-Amz-Signature': signed,
  })}`;
  const clientHeaders: Record<string, string> = {};
  for (const [name, value] of Object.entries(input.headers)) {
    if (name.toLowerCase() === 'host') continue;
    clientHeaders[name] = value;
  }
  return { url, signedHeaders: clientHeaders };
}

export function authorizeS3Request(input: {
  method: string;
  host: string;
  canonicalUri: string;
  query?: Record<string, string>;
  accessKeyId: string;
  secretAccessKey: string;
  headers?: Record<string, string>;
  payload: string | Buffer;
  now: Date;
}): Record<string, string> {
  const { amzDate, dateStamp } = formatAmzDate(input.now);
  const payloadHash = sha256Hex(input.payload);
  const headers = {
    host: input.host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': amzDate,
    ...(input.headers ?? {}),
  };
  const { canonicalRequest, signedHeaders } = buildCanonicalRequest({
    method: input.method,
    canonicalUri: input.canonicalUri,
    query: input.query ?? {},
    headers,
    payloadHash,
  });
  const signed = signatureFor({
    secretAccessKey: input.secretAccessKey,
    dateStamp,
    stringToSign: stringToSign(amzDate, dateStamp, canonicalRequest),
  });
  return {
    ...headers,
    authorization: `AWS4-HMAC-SHA256 Credential=${input.accessKeyId}/${credentialScope(
      dateStamp,
    )}, SignedHeaders=${signedHeaders}, Signature=${signed}`,
  };
}
