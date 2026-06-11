import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const functionSource = readFileSync(
  new URL('../../../supabase/functions/process-progress-photo/index.ts', import.meta.url),
  'utf8',
);

const functionConfig = readFileSync(
  new URL('../../../supabase/functions/process-progress-photo/config.toml', import.meta.url),
  'utf8',
);

const webPhotoUtils = readFileSync(
  new URL('../../../apps/web/src/utils/photo-utils.ts', import.meta.url),
  'utf8',
);

const iosPhotoUploadManager = readFileSync(
  new URL('../../../apps/ios/LogYourBody/Services/PhotoUploadManager.swift', import.meta.url),
  'utf8',
);

describe('process-progress-photo auth boundary', () => {
  it('requires a verified user token before processing photos', () => {
    expect(functionConfig).toContain('verify_jwt = true');
    expect(functionSource).toContain("req.headers.get('Authorization')");
    expect(functionSource).toContain('supabase.auth.getUser(token)');
    expect(functionSource).toContain(
      "return jsonResponse({ error: 'Missing or invalid authorization header' }, 401)",
    );
    expect(functionSource).toContain("return jsonResponse({ error: 'Invalid token' }, 401)");
  });

  it('checks metric and storage ownership before signing or uploading the photo', () => {
    expect(functionSource).toContain('!normalizedStoragePath.startsWith(`${user.id}/`)');
    expect(functionSource).toContain(".select('id, user_id')");
    expect(functionSource).toContain('metric.user_id !== user.id');

    expect(functionSource.indexOf(".select('id, user_id')")).toBeLessThan(
      functionSource.indexOf('.createSignedUrl(normalizedStoragePath'),
    );
    expect(functionSource.indexOf('metric.user_id !== user.id')).toBeLessThan(
      functionSource.indexOf('fetch(\n      `https://api.cloudinary.com'),
    );
  });

  it('keeps the user predicate on the final service-role update', () => {
    expect(functionSource).toContain(".eq('id', metricsId)\n      .eq('user_id', user.id)");
    expect(functionSource).toContain(
      "return jsonResponse({ error: 'Failed to update metrics photo' }, 500)",
    );
  });

  it('does not let clients call the function with the anon key as bearer auth', () => {
    expect(webPhotoUtils).toContain('await supabase.auth.getSession()');
    expect(webPhotoUtils).toContain('Authorization: `Bearer ${accessToken}`');
    expect(webPhotoUtils).not.toContain('Authorization: `Bearer ${supabaseAnonKey}`');

    expect(iosPhotoUploadManager).toContain(
      'private func authenticatedJWT() async throws -> String',
    );
    expect(iosPhotoUploadManager).toContain('let token = try await authenticatedJWT()');
    expect(iosPhotoUploadManager).toContain(
      'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
    );
    expect(iosPhotoUploadManager).not.toContain(
      'request.setValue("Bearer \\(Constants.supabaseAnonKey)"',
    );
  });
});
