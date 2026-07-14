import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

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

async function capturedAtFor(source) {
  try {
    const value = execFileSync('git', ['log', '-1', '--format=%cI', '--', source], {
      cwd: root,
      encoding: 'utf8',
    }).trim();
    if (value) return value;
  } catch {
    // A source archive may not include git metadata; file mtime is the safe fallback.
  }

  return (await stat(path.join(root, source))).mtime.toISOString();
}

const manifest = {};

for (const [id, asset] of Object.entries(assets)) {
  const sourcePath = path.join(root, asset.source);
  const outputPath = path.join(root, asset.output);
  const sourceBuffer = await readFile(sourcePath);
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
    capturedAt: await capturedAtFor(asset.source),
  };
}

const manifestPath = path.join(root, 'apps/web/src/generated/marketing-product-assets.json');
await mkdir(path.dirname(manifestPath), { recursive: true });
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`Synced ${Object.keys(manifest).length} canonical iOS marketing assets.`);
