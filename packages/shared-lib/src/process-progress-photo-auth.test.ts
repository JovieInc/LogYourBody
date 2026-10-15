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

describe('first-party progress photo auth boundary', () => {
  it('requires a verified bearer token before the photo store stub runs', () => {
    expect(photosRoute).toContain('fetchUserInfo(token)');
    expect(photosRoute).toContain("error: 'unauthorized'");
    expect(photosRoute).toContain("error: 'photo_store_unavailable'");
    expect(photosRoute).toContain('noStoreJson');
    expect(photosRoute).toContain('503');
  });

  it('keeps native photo upload on the first-party bearer API', () => {
    expect(iosPhotoUploadManager).toContain(
      'private func authenticatedJWT(for ownership: AuthManager.ProfileSessionOwnership) async throws -> String',
    );
    expect(iosPhotoUploadManager).toContain(
      'let token = try await authenticatedJWT(for: ownership)',
    );
    expect(iosPhotoUploadManager).toMatch(
      /private func authenticatedJWT\(for ownership: AuthManager\.ProfileSessionOwnership\) async throws -> String \{\s*guard authManager\.ownsAccountSession\(ownership\),\s*let token = await accessTokenProvider\(\),\s*authManager\.ownsAccountSession\(ownership\) else \{\s*throw PhotoError\.notAuthenticated\s*\}\s*return token\s*\}/,
    );
    expect(iosPhotoUploadManager).toContain('/api/auth/mobile/photos');
    expect(iosPhotoUploadManager).toContain(
      'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
    );
    expect(iosPhotoUploadManager).not.toContain('storage/v1');
    expect(iosPhotoUploadManager).not.toContain('process-progress-photo');
  });
});
