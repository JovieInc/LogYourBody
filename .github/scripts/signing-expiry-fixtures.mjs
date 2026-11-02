import { daysUntil } from './signing-expiry.mjs';

export const NOW = Date.parse('2026-10-25T00:00:00Z');
export const SECRET_CONTENT = 'M'.repeat(40) + 'SECRETCONTENTONLYFORTEST' + 'A'.repeat(40);
export const SECRET_SERIAL = 'SERIALSHOULDNOTLEAK99';
export const SECRET_KEY = 'ABCD123456';
export const SECRET_PASSWORD = 'match-secret-value';

export const REQUIRED_BUNDLE_IDS = ['com.logyourbody.app', 'com.logyourbody.app.rest-timer'];
export const isoDays = (days) => new Date(NOW + days * 86_400_000).toISOString();

export function assets({
  certDays = [200],
  profileDays = [180],
  unusedCertDays = [],
  key = { authenticated: true, expirationDate: null },
  requiredBundleIds = REQUIRED_BUNDLE_IDS,
  certificateType = 'IOS_DISTRIBUTION',
} = {}) {
  const certificates = certDays.map((days) => ({
    certificateType,
    expirationDate: isoDays(days),
  }));
  const valid = certificates.filter(
    (certificate) => daysUntil(certificate.expirationDate, NOW) >= 0,
  );
  const embedded = (valid.length > 0 ? valid : certificates).map((certificate) => ({
    ...certificate,
  }));
  return {
    certificatesReadable: true,
    profilesReadable: true,
    requiredBundleIds,
    certificates: [
      ...certificates,
      ...unusedCertDays.map((days) => ({
        certificateType,
        expirationDate: isoDays(days),
      })),
    ],
    profiles: requiredBundleIds.map((bundleId, index) => ({
      bundleId,
      profileType: 'IOS_APP_STORE',
      profileState: 'ACTIVE',
      expirationDate: isoDays(profileDays[Math.min(index, Math.max(profileDays.length - 1, 0))]),
      certificateLink: embedded.length > 0 ? 'ok' : 'unreadable',
      certificates: embedded,
    })),
    apiKey: key,
  };
}

