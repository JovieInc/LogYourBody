import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { logYourBodyStorefront } from '../src/storefronts/logyourbody.mjs';

export function pngInfo(buffer) {
  if (buffer.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
    throw new Error('screenshot must be a PNG');
  }

  let offset = 8;
  let width;
  let height;
  let colorType;
  let hasTransparencyChunk = false;

  while (offset + 12 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.subarray(offset + 4, offset + 8).toString('ascii');
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;

    if (dataEnd + 4 > buffer.length) throw new Error('invalid PNG chunk length');

    if (type === 'IHDR') {
      width = buffer.readUInt32BE(dataStart);
      height = buffer.readUInt32BE(dataStart + 4);
      colorType = buffer[dataStart + 9];
    } else if (type === 'tRNS') {
      hasTransparencyChunk = true;
    }

    offset = dataEnd + 4;
    if (type === 'IEND') break;
  }

  if (!width || !height) throw new Error('PNG is missing IHDR dimensions');

  return {
    width,
    height,
    hasAlpha: colorType === 4 || colorType === 6 || hasTransparencyChunk,
  };
}

export function gitBlobSha(buffer) {
  const header = Buffer.from(`blob ${buffer.length}\0`);
  return createHash('sha1').update(header).update(buffer).digest('hex');
}

export async function collectScreenshotAssets(repoRoot) {
  const assets = [];

  for (const locale of logYourBodyStorefront.locales) {
    const directory = resolve(repoRoot, 'apps/ios/fastlane/screenshots', locale.id);
    const entries = await readdir(directory, { withFileTypes: true }).catch(() => []);
    const filenames = entries
      .filter((entry) => entry.isFile() && extname(entry.name).toLowerCase() === '.png')
      .map((entry) => entry.name)
      .sort();

    for (const filename of filenames) {
      const absolutePath = resolve(directory, filename);
      const buffer = await readFile(absolutePath);
      const info = pngInfo(buffer);

      assets.push({
        locale: locale.id,
        path: relative(repoRoot, absolutePath).split(sep).join('/'),
        filename,
        width: info.width,
        height: info.height,
        hasAlpha: info.hasAlpha,
        gitBlobSha: gitBlobSha(buffer),
        sourceKind: 'ios-fastlane-capture',
        truthStatus: 'real-app-capture',
      });
    }
  }

  return assets;
}
