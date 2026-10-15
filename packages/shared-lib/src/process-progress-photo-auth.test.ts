import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const photosRoute = readFileSync(
  new URL('../../../apps/web/src/app/api/auth/mobile/photos/route.ts', import.meta.url),
  'utf8',
);

const iosPhotoUploadManager = readFileSync(
  new URL('../../../apps/ios/LogYourBody/Services/PhotoUploadManager.swift', import.meta.url),
  'utf8',
);

// Static cross-platform source contract; native lifecycle tests remain separate execution proof.
function expectOwnerScopedPhotoBearer(source: string) {
  const jwtBody = source.match(
    /private func authenticatedJWT\(for ownership: AuthManager\.ProfileSessionOwnership\) async throws -> String \{([\s\S]*?)\n {4}\}/,
  )?.[1];
  expect(jwtBody).toBeDefined();
  expect(jwtBody).toMatch(
    /^\s*guard authManager\.ownsAccountSession\(ownership\),\s*let token = await accessTokenProvider\(\),\s*authManager\.ownsAccountSession\(ownership\) else \{\s*throw PhotoError\.notAuthenticated\s*\}\s*return token\s*$/,
  );
  expect(jwtBody).toContain('return token');

  const requestBody = source.match(/private func requestRemotePhotoStore\(([\s\S]*?)\n {4}\}/)?.[1];
  expect(requestBody).toBeDefined();
  expect(requestBody).toContain('ownership: AuthManager.ProfileSessionOwnership');
  expect(requestBody).toContain('let token = try await authenticatedJWT(for: ownership)');
  expect(requestBody).toContain('/api/auth/mobile/photos');
  expect(requestBody).toContain('request.httpMethod = "POST"');
  expect(requestBody).toContain(
    'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
  );
  const tokenOffset =
    requestBody?.indexOf('let token = try await authenticatedJWT(for: ownership)') ?? -1;
  const bearerOffset =
    requestBody?.indexOf(
      'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
    ) ?? -1;
  const sendOffset = requestBody?.indexOf('data(for: request)') ?? -1;
  expect(tokenOffset).toBeGreaterThanOrEqual(0);
  expect(bearerOffset).toBeGreaterThan(tokenOffset);
  expect(sendOffset).toBeGreaterThan(bearerOffset);
  expect(source).not.toContain('storage/v1');
  expect(source).not.toContain('process-progress-photo');
}

describe('first-party progress photo auth boundary', () => {
  it('requires a verified bearer token before the photo store stub runs', () => {
    expect(photosRoute).toContain('fetchUserInfo(token)');
    expect(photosRoute).toContain("error: 'unauthorized'");
    expect(photosRoute).toContain("error: 'photo_store_unavailable'");
    expect(photosRoute).toContain('noStoreJson');
    expect(photosRoute).toContain('503');
  });

  it('keeps native photo upload on the owner-scoped first-party bearer API', () => {
    expectOwnerScopedPhotoBearer(iosPhotoUploadManager);
  });

  it.each<[string, (source: string) => string]>([
    [
      'early return bypasses the ownership guard',
      (source: string) =>
        source.replace(
          'private func authenticatedJWT(for ownership: AuthManager.ProfileSessionOwnership) async throws -> String {',
          'private func authenticatedJWT(for ownership: AuthManager.ProfileSessionOwnership) async throws -> String {\n        return "synthetic-bypass-token"',
        ),
    ],
    [
      'missing owner check before token suspension',
      (source: string) =>
        source.replace('guard authManager.ownsAccountSession(ownership),', 'guard true,'),
    ],
    [
      'missing owner check after token suspension',
      (source: string) =>
        source.replace(
          /(let token = await accessTokenProvider\(\),\s*)authManager\.ownsAccountSession\(ownership\)(\s+else)/,
          '$1true$2',
        ),
    ],
    [
      'request does not forward captured ownership',
      (source: string) =>
        source.replace(
          'let token = try await authenticatedJWT(for: ownership)',
          'let token = try await authenticatedJWT()',
        ),
    ],
    [
      'request omits the bearer Authorization header',
      (source: string) =>
        source.replace(
          'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
          'request.setValue("synthetic", forHTTPHeaderField: "X-Test")',
        ),
    ],
  ])('rejects a weakened native source contract: %s', (_reason, weaken) => {
    const weakened = weaken(iosPhotoUploadManager);
    expect(weakened).not.toBe(iosPhotoUploadManager);
    expect(() => expectOwnerScopedPhotoBearer(weakened)).toThrow();
  });

  it('tracks both external source reads in the shared-lib Turbo test inputs', () => {
    const turbo = JSON.parse(readFileSync(new URL('../turbo.json', import.meta.url), 'utf8'));
    expect(turbo.tasks.test.inputs).toEqual(
      expect.arrayContaining([
        '$TURBO_ROOT$/apps/ios/LogYourBody/Services/PhotoUploadManager.swift',
        '$TURBO_ROOT$/apps/web/src/app/api/auth/mobile/photos/route.ts',
      ]),
    );
  });
});
