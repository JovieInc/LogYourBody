import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
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

function capturedAtFor(source, sourceSha256, previous) {
  // Unchanged image bytes retain their capture age, including in shallow CI clones.
  if (previous?.source === source && previous.sourceSha256 === sourceSha256) {
    if (!Number.isFinite(Date.parse(previous.capturedAt))) {
      throw new Error(`Invalid capture provenance date: ${source}`);
    }
    return previous.capturedAt;
  }

  const git = (...args) =>
    execFileSync('git', args, {
      cwd: root,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 10_000,
      maxBuffer: 16 * 1024 * 1024,
    });
  try {
    if (git('rev-parse', '--is-shallow-repository').toString().trim() !== 'false') {
      throw new Error('Fetch complete history before syncing a changed capture');
    }
    const [commit, timestamp] = git('log', '-1', '--format=%H%n%cI', '--', source)
      .toString()
      .trim()
      .split('\n');
    if (
      !Number.isFinite(Date.parse(timestamp)) ||
      sha256(git('show', `${commit}:${source}`)) !== sourceSha256
    ) {
      throw new Error('The capture must match committed source bytes');
    }
    return timestamp;
  } catch (error) {
    throw new Error(`Missing capture provenance for ${source}: ${error.message}`);
  }
}

const manifestPath = path.join(root, 'apps/web/src/generated/marketing-product-assets.json');
const previous = await readFile(manifestPath, 'utf8')
  .then(JSON.parse)
  .catch((error) => {
    if (error.code === 'ENOENT') return {};
    throw error;
  });
const manifest = {};

for (const [id, asset] of Object.entries(assets)) {
  const sourceBuffer = await readFile(path.join(root, asset.source));
  const sourceSha256 = sha256(sourceBuffer);
  const { width, height } = pngDimensions(sourceBuffer);

  manifest[id] = {
    ...asset,
    width,
    height,
    sourceSha256,
    outputSha256: sourceSha256,
    capturedAt: capturedAtFor(asset.source, sourceSha256, previous[id]),
  };
}

// Validate every asset's provenance before updating any public output or receipt.
for (const asset of Object.values(manifest)) {
  const outputPath = path.join(root, asset.output);
  await mkdir(path.dirname(outputPath), { recursive: true });
  await copyFile(path.join(root, asset.source), outputPath);
  asset.outputSha256 = sha256(await readFile(outputPath));
}

await mkdir(path.dirname(manifestPath), { recursive: true });
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`Synced ${Object.keys(manifest).length} canonical iOS marketing assets.`);
