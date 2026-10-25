import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');
const home = 'apps/ios/LogYourBody/Views/HomeV2/';

it('composes the glass filmstrip inside the existing ruler and selection callback (LYB-85)', () => {
  const ruler = read(`${home}HomeV2PhotoTimelineRuler.swift`);
  const surface = read(`${home}HomeV2Surface.swift`);
  const viewer = read(`${home}HomeV2PhotoViewer.swift`);
  expect(ruler).toContain('HomeV2FilmstripPolicy.isEnabled()');
  expect(ruler).toContain('HomeV2Filmstrip(photoURLs: photoURLs, selected: selected)');
  expect(ruler).toContain('onSelect(index)');
  expect(ruler).not.toMatch(/@State[^\n]*(?:selected|selection)/);
  expect(surface).toContain('photoURLs: timeline.metrics.reversed().map(\\.photoUrl)');
  expect(surface).toContain('height: geometry.size.width / HomeV2Tokens.photoAspectRatio');
  expect(viewer).toContain('photoURLs: chronological.map { bodyMetrics[$0].photoUrl }');
  const strip = surface.slice(
    surface.indexOf('struct HomeV2Filmstrip: View'),
    surface.indexOf('struct SubjectPlateView'),
  );
  expect(strip).toContain('.systemBGlassSurface(');
  expect(strip).not.toMatch(/@Binding|ScrollView|\.gesture\(|Button\s*\{/);
  expect(strip).toContain('usesThumbnail: true');
  expect(strip).toContain('.task(id: adjacentURLs)');
  const ui = read('apps/ios/LogYourBodyUITests/HomeV2PhotoViewerLayoutUITests.swift');
  expect(ui).toContain('assertGlassFilmstripKeepsPhotoDateAndWeightTogether(in: app)');
  expect(ui).toContain('"-lybUITestGlassFilmstrip"');
});

it('decodes filmstrip images directly to thumbnail pixels and isolates their cache entries', () => {
  const pipeline = read('apps/ios/LogYourBody/Services/ImageCacheService.swift');
  expect(pipeline).toContain('CGImageSourceCreateThumbnailAtIndex');
  expect(pipeline).toContain('kCGImageSourceCreateThumbnailWithTransform: true');
  expect(pipeline).toContain('kCGImageSourceThumbnailMaxPixelSize: maxPixelSize');
  expect(pipeline).toContain('"thumbnail:\\(urlString)"');
  expect(pipeline).toContain('guard !Task.isCancelled else { return }');
});
