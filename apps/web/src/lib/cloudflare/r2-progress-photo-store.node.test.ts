/** @jest-environment node */

import {
  createProgressPhotoUploadTicket,
  deleteOwnedProgressPhotos,
  parsePublicBaseUrl,
  progressPhotoObjectKey,
  progressPhotoOwnerPrefix,
  publicProgressPhotoUrl,
  readR2PhotoStoreConfig,
} from './r2-progress-photo-store';
import { buildCanonicalRequest, formatAmzDate, presignS3Request } from './r2-aws-v4';

const fixtureConfig = {
  accountId: 'a1b2c3d4e5f607182930aabbccddeeff',
  accessKeyId: 'AKIAFIXTUREACCESS',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYFIXTUREKEY',
  bucket: 'lyb-progress-photos',
  publicBaseUrl: 'https://photos.logyourbody.com',
  apiHost: 'a1b2c3d4e5f607182930aabbccddeeff.r2.cloudflarestorage.com',
};

describe('readR2PhotoStoreConfig', () => {
  it('fails closed when any required variable is missing or unsafe', () => {
    expect(readR2PhotoStoreConfig({})).toBeNull();
    expect(
      readR2PhotoStoreConfig({
        CLOUDFLARE_ACCOUNT_ID: 'a1b2c3d4e5f607182930aabbccddeeff',
        CLOUDFLARE_R2_ACCESS_KEY_ID: 'key',
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'secret',
        CLOUDFLARE_R2_BUCKET: 'lyb-progress-photos',
      }),
    ).toBeNull();
    expect(
      readR2PhotoStoreConfig({
        CLOUDFLARE_ACCOUNT_ID: '../escape',
        CLOUDFLARE_R2_ACCESS_KEY_ID: 'key',
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'secret',
        CLOUDFLARE_R2_BUCKET: 'lyb-progress-photos',
        CLOUDFLARE_R2_PUBLIC_BASE_URL: 'https://photos.logyourbody.com',
      }),
    ).toBeNull();
    expect(
      readR2PhotoStoreConfig({
        CLOUDFLARE_ACCOUNT_ID: 'a1b2c3d4e5f607182930aabbccddeeff',
        CLOUDFLARE_R2_ACCESS_KEY_ID: 'key',
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'secret',
        CLOUDFLARE_R2_BUCKET: 'lyb-progress-photos',
        CLOUDFLARE_R2_PUBLIC_BASE_URL: 'http://photos.logyourbody.com',
      }),
    ).toBeNull();
  });

  it('accepts a complete HTTPS public base and account-scoped API host', () => {
    expect(
      readR2PhotoStoreConfig({
        CLOUDFLARE_ACCOUNT_ID: fixtureConfig.accountId,
        CLOUDFLARE_R2_ACCESS_KEY_ID: fixtureConfig.accessKeyId,
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: fixtureConfig.secretAccessKey,
        CLOUDFLARE_R2_BUCKET: fixtureConfig.bucket,
        CLOUDFLARE_R2_PUBLIC_BASE_URL: 'https://photos.logyourbody.com/',
      }),
    ).toEqual(fixtureConfig);
  });
});

describe('progress photo object identity', () => {
  it('scopes keys to the authenticated owner and rejects unsafe metric ids', () => {
    const now = new Date('2026-08-17T18:00:00.000Z');
    expect(
      progressPhotoObjectKey({
        userId: 'owner-a',
        metricsId: 'metric-owned',
        contentType: 'image/jpeg',
        now,
      }),
    ).toBe('progress-photos/owner-a/metric-owned_1786989600000.jpg');
    expect(() =>
      progressPhotoObjectKey({
        userId: 'owner-a',
        metricsId: '../victim',
        contentType: 'image/jpeg',
        now,
      }),
    ).toThrow('invalid_metrics_id');
  });

  it('hashes owner ids that are not safe path segments', () => {
    const prefix = progressPhotoOwnerPrefix('owner/../victim');
    expect(prefix.startsWith('progress-photos/')).toBe(true);
    expect(prefix).not.toContain('..');
    expect(prefix).not.toContain('victim');
  });

  it('builds a public HTTPS delivery URL from the configured base', () => {
    expect(parsePublicBaseUrl('https://photos.logyourbody.com/cdn/')).toBe(
      'https://photos.logyourbody.com/cdn',
    );
    expect(
      publicProgressPhotoUrl(fixtureConfig, 'progress-photos/owner-a/metric-owned_1.jpg'),
    ).toBe('https://photos.logyourbody.com/progress-photos/owner-a/metric-owned_1.jpg');
  });
});

describe('presigned R2 PUT tickets', () => {
  it('signs a PUT for the owner key and returns only client-needed headers', () => {
    const now = new Date('2026-08-17T18:00:00.000Z');
    const ticket = createProgressPhotoUploadTicket({
      config: fixtureConfig,
      userId: 'owner-a',
      metricsId: 'metric-owned',
      contentType: 'image/jpeg',
      now,
    });

    expect(ticket.uploadMethod).toBe('PUT');
    expect(ticket.expiresIn).toBe(300);
    expect(ticket.objectKey).toBe('progress-photos/owner-a/metric-owned_1786989600000.jpg');
    expect(ticket.storagePath).toBe(ticket.objectKey);
    expect(ticket.photoUrl).toBe(
      'https://photos.logyourbody.com/progress-photos/owner-a/metric-owned_1786989600000.jpg',
    );
    expect(ticket.uploadHeaders).toEqual({ 'content-type': 'image/jpeg' });

    const upload = new URL(ticket.uploadUrl);
    expect(upload.protocol).toBe('https:');
    expect(upload.host).toBe(fixtureConfig.apiHost);
    expect(upload.pathname).toBe(
      '/lyb-progress-photos/progress-photos/owner-a/metric-owned_1786989600000.jpg',
    );
    expect(upload.searchParams.get('X-Amz-Algorithm')).toBe('AWS4-HMAC-SHA256');
    expect(upload.searchParams.get('X-Amz-SignedHeaders')).toBe('content-type;host');
    expect(upload.searchParams.get('X-Amz-Expires')).toBe('300');
    expect(upload.searchParams.get('X-Amz-Signature')).toMatch(/^[a-f0-9]{64}$/);
    expect(ticket.uploadUrl).not.toContain(fixtureConfig.secretAccessKey);
  });

  it('keeps SigV4 canonical requests stable for a frozen clock', () => {
    const now = new Date('2026-08-17T18:00:00.000Z');
    const { amzDate, dateStamp } = formatAmzDate(now);
    expect(amzDate).toBe('20260817T180000Z');
    expect(dateStamp).toBe('20260817');

    const { canonicalRequest, signedHeaders } = buildCanonicalRequest({
      method: 'PUT',
      canonicalUri: '/lyb-progress-photos/progress-photos/owner-a/file.jpg',
      query: {
        'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
        'X-Amz-Credential': 'AKIA/20260817/auto/s3/aws4_request',
        'X-Amz-Date': amzDate,
        'X-Amz-Expires': '300',
        'X-Amz-SignedHeaders': 'content-type;host',
      },
      headers: {
        'content-type': 'image/jpeg',
        host: fixtureConfig.apiHost,
      },
      payloadHash: 'UNSIGNED-PAYLOAD',
    });

    expect(signedHeaders).toBe('content-type;host');
    expect(canonicalRequest).toContain(
      'PUT\n/lyb-progress-photos/progress-photos/owner-a/file.jpg\n',
    );
    expect(canonicalRequest).toContain('content-type:image/jpeg\n');
    expect(canonicalRequest.endsWith('UNSIGNED-PAYLOAD')).toBe(true);

    const first = presignS3Request({
      method: 'PUT',
      host: fixtureConfig.apiHost,
      canonicalUri: '/lyb-progress-photos/progress-photos/owner-a/file.jpg',
      accessKeyId: fixtureConfig.accessKeyId,
      secretAccessKey: fixtureConfig.secretAccessKey,
      headers: { 'content-type': 'image/jpeg' },
      expiresIn: 300,
      now,
    });
    const second = presignS3Request({
      method: 'PUT',
      host: fixtureConfig.apiHost,
      canonicalUri: '/lyb-progress-photos/progress-photos/owner-a/file.jpg',
      accessKeyId: fixtureConfig.accessKeyId,
      secretAccessKey: fixtureConfig.secretAccessKey,
      headers: { 'content-type': 'image/jpeg' },
      expiresIn: 300,
      now,
    });
    expect(first.url).toBe(second.url);
    expect(first.url).toContain('X-Amz-Signature=');
  });
});

describe('deleteOwnedProgressPhotos', () => {
  it('is a no-op when R2 is not configured', async () => {
    const fetcher = jest.fn();
    await deleteOwnedProgressPhotos('owner-a', { env: {}, fetcher });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('lists then deletes only objects under the owner prefix', async () => {
    const fetcher = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (init?.method === 'GET') {
        expect(url).toContain('prefix=progress-photos%2Fowner-a%2F');
        return new Response(
          `<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>progress-photos/owner-a/one.jpg</Key></Contents></ListBucketResult>`,
          { status: 200 },
        );
      }
      expect(init?.method).toBe('DELETE');
      expect(url).toContain('/lyb-progress-photos/progress-photos/owner-a/one.jpg');
      return new Response(null, { status: 204 });
    });

    await deleteOwnedProgressPhotos('owner-a', {
      env: {
        CLOUDFLARE_ACCOUNT_ID: fixtureConfig.accountId,
        CLOUDFLARE_R2_ACCESS_KEY_ID: fixtureConfig.accessKeyId,
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: fixtureConfig.secretAccessKey,
        CLOUDFLARE_R2_BUCKET: fixtureConfig.bucket,
        CLOUDFLARE_R2_PUBLIC_BASE_URL: fixtureConfig.publicBaseUrl,
      },
      fetcher: fetcher as unknown as typeof fetch,
      now: new Date('2026-08-17T18:00:00.000Z'),
    });

    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it('fails closed when a list result escapes the owner prefix', async () => {
    const fetcher = jest.fn(async () => {
      return new Response(
        `<ListBucketResult><Contents><Key>progress-photos/victim/one.jpg</Key></Contents></ListBucketResult>`,
        { status: 200 },
      );
    });

    await expect(
      deleteOwnedProgressPhotos('owner-a', {
        env: {
          CLOUDFLARE_ACCOUNT_ID: fixtureConfig.accountId,
          CLOUDFLARE_R2_ACCESS_KEY_ID: fixtureConfig.accessKeyId,
          CLOUDFLARE_R2_SECRET_ACCESS_KEY: fixtureConfig.secretAccessKey,
          CLOUDFLARE_R2_BUCKET: fixtureConfig.bucket,
          CLOUDFLARE_R2_PUBLIC_BASE_URL: fixtureConfig.publicBaseUrl,
        },
        fetcher: fetcher as unknown as typeof fetch,
      }),
    ).rejects.toThrow('r2_list_returned_unowned_object');
  });
});
