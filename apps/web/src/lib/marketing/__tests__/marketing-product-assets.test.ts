/**
 * @jest-environment node
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import productAssets from '@/generated/marketing-product-assets.json';

function sha256(filePath: string) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

describe('canonical marketing product assets', () => {
  it('keeps the public product screenshot byte-identical to the iOS Fastlane capture', () => {
    const root = path.resolve(process.cwd(), '../..');
    const source = path.join(root, productAssets.weightLog.source);
    const output = path.join(root, productAssets.weightLog.output);

    expect(sha256(source)).toBe(productAssets.weightLog.sourceSha256);
    expect(sha256(output)).toBe(productAssets.weightLog.outputSha256);
    expect(productAssets.weightLog.sourceSha256).toBe(productAssets.weightLog.outputSha256);
  });

  it('requires a recent canonical product capture for marketing use', () => {
    const ageMs = Date.now() - Date.parse(productAssets.weightLog.capturedAt);
    expect(ageMs).toBeGreaterThanOrEqual(0);
    expect(ageMs).toBeLessThanOrEqual(60 * 24 * 60 * 60 * 1000);
  });

  it('records actual PNG dimensions instead of advertising a viewport guess', () => {
    expect(productAssets.weightLog).toEqual(expect.objectContaining({ width: 1242, height: 2688 }));
    expect(productAssets.appIcon).toEqual(expect.objectContaining({ width: 1024, height: 1024 }));
  });
});
