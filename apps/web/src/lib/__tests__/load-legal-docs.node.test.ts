/** @jest-environment node */
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { logYourBody } from '@jovieinc/product-registry';
import { loadLegalDocument } from '../load-legal-docs';

describe('loadLegalDocument', () => {
  afterEach(() => jest.restoreAllMocks());

  it('loads the unchanged canonical consumer health policy', async () => {
    const policy = await fs.readFile(
      path.resolve(process.cwd(), '../../shared/legal/consumer-health-data-policy.md'),
      'utf8',
    );
    expect(await loadLegalDocument('consumerHealth')).toBe(policy);
  });

  it('returns the policy-specific fallback when the file cannot be read', async () => {
    const error = new Error('Document unavailable');
    jest.spyOn(fs, 'readFile').mockRejectedValueOnce(error);
    const logError = jest.spyOn(console, 'error').mockImplementation(() => {});

    const fallback = await loadLegalDocument('consumerHealth');

    expect(fallback).toContain('# Consumer Health Data Privacy Policy');
    expect(fallback).toContain(logYourBody.contacts.privacy);
    expect(logError).toHaveBeenCalledWith('Failed to load legal document consumerHealth:', error);
  });
});
