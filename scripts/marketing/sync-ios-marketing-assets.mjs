import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const manifestPath = path.join(root, 'apps/web/src/generated/marketing-product-assets.json');
let previousManifest = {};
try {
  previousManifest = JSON.parse(await readFile(manifestPath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

const assets = {
  weightLog: {
    source: 'apps/ios/fastlane/screenshots/en-US/01_APP_IPHONE_65.png',
    output: 'apps/web/public/product-screenshots/ios/weight-log.png',
    publicUrl: '/product-screenshots/ios/weight-log.png',
    sourceKind: 'ios-fastlane-capture',
    truthStatus: 'real-app-capture',
  },
  appIcon: {
    source:
      'apps/ios/LogYourBody/Assets.xcassets/AppIcon.appiconset/lyb_icon-iOS-Dark-1024x1024@1x.png',
    output: 'apps/web/public/brand/logyourbody-app-icon.png',
    publicUrl: '/brand/logyourbody-app-icon.png',
    sourceKind: 'ios-asset-catalog',
    truthStatus: 'canonical-brand-asset',
  },
};

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function pngDimensions(buffer) {
  const pngSignature = '89504e470d0a1a0a';
  if (buffer.subarray(0, 8).toString('hex') !== pngSignature) {
    throw new Error('Marketing asset is not a PNG');
  }

  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

function capturedAtFor(id, source, sourceBuffer) {
  // Capture provenance follows the image bytes, never checkout or synthetic merge time.
  const previous = previousManifest[id];
  if (
    previous?.source === source &&
    previous.sourceSha256 === sha256(sourceBuffer) &&
    Number.isFinite(Date.parse(previous.capturedAt))
  ) {
    return previous.capturedAt;
  }

  try {
    const options = { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] };
    if (
      execFileSync('git', ['rev-parse', '--is-shallow-repository'], options).toString().trim() !==
      'false'
    ) {
      throw new Error('Shallow history cannot establish capture provenance');
    }
    const committed = execFileSync('git', ['show', `HEAD:${source}`], options);
    if (sha256(committed) !== sha256(sourceBuffer)) {
      throw new Error('Uncommitted asset has no capture provenance');
    }
    const value = execFileSync('git', ['log', '-1', '--format=%cI', '--', source], {
      ...options,
      encoding: 'utf8',
    }).trim();
    if (Number.isFinite(Date.parse(value))) return value;
  } catch {
    // Extraction time and shallow merge commits are not evidence of a new capture.
  }
  throw new Error(
    `Cannot establish capture timestamp for ${source}; restore a hash-matching manifest or regenerate from complete, committed asset history.`,
  );
}

const manifest = {};

for (const [id, asset] of Object.entries(assets)) {
  const sourcePath = path.join(root, asset.source);
  const outputPath = path.join(root, asset.output);
  const sourceBuffer = await readFile(sourcePath);
  const capturedAt = capturedAtFor(id, asset.source, sourceBuffer);
  await mkdir(path.dirname(outputPath), { recursive: true });
  await copyFile(sourcePath, outputPath);
  const outputBuffer = await readFile(outputPath);
  const { width, height } = pngDimensions(outputBuffer);

  manifest[id] = {
    ...asset,
    width,
    height,
    sourceSha256: sha256(sourceBuffer),
    outputSha256: sha256(outputBuffer),
    capturedAt,
  };
}

await mkdir(path.dirname(manifestPath), { recursive: true });
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`Synced ${Object.keys(manifest).length} canonical iOS marketing assets.`);
