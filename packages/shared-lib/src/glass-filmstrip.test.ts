import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { homePhotoStageFindings } from './home-stage-reservation';

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
  const states = read(`${home}HomeV2SystemStates.swift`);
  expect(states).toContain('HomeV2StageReservation.size(');
  expect(states).toContain('.homeV2ReservedStage(');
  expect(states).not.toContain('height: geometry.size.width / HomeV2Tokens.photoAspectRatio');
  expect(
    homePhotoStageFindings(
      surface,
      read(`${home}HomeV2Tokens.swift`),
      read(`${home}HomeV2Policy.swift`),
    ),
  ).toEqual([]);
  expect(viewer).toContain('photoURLs: chronological.map { bodyMetrics[$0].photoUrl }');
  const strip = surface.slice(
    surface.indexOf('struct HomeV2Filmstrip: View'),
    surface.indexOf('struct SubjectPlateView'),
  );
  expect(strip).toContain('.systemBGlassSurface(');
  expect(strip).not.toMatch(/@Binding|ScrollView|\.gesture\(|Button\s*\{/);
  expect(strip).toContain('usesThumbnail: true');
  expect(strip).toContain('thumbIdentity');
  expect(strip).toContain('.task(id: adjacentURLs)');
  const ui = read('apps/ios/LogYourBodyUITests/HomeV2PhotoViewerLayoutUITests.swift');
  expect(ui).toContain('assertGlassFilmstripKeepsPhotoDateAndWeightTogether(in: app)');
  expect(ui).toContain('"-lybUITestGlassFilmstrip"');
});

it('rejects a Home card that leaves the shared photo-stage reservation', () => {
  const layout =
    'static func stageHeight(width: CGFloat, height: CGFloat) -> CGFloat {\n' +
    'let fourByFive = width / HomeV2Tokens.photoAspectRatio\n' +
    'return min(fourByFive, available)\n}';
  const inline = 'height: geometry.size.width / HomeV2Tokens.photoAspectRatio';
  const reserved = 'enum HomeV2StageReservation {} func homeV2ReservedStage';
  expect(homePhotoStageFindings(inline, reserved, layout)).toContain(
    'HomeV2Surface sizes the timeline outside HomeV2StageReservation',
  );
  const surface = 'HomeV2StageReservation.size(\nhasPhoto ? .photo : .noPhoto\n';
  const dropped =
    'enum HomeV2StageReservation { case .photo, .noPhoto, .loading, .failedLoad, .offline: height = 1 } func homeV2ReservedStage';
  expect(homePhotoStageFindings(surface, dropped, layout)).toEqual([
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  ]);
  const widthOnly =
    'enum HomeV2StageReservation { case .photo, .noPhoto, .loading, .failedLoad, .offline:\n' +
    'height = safeWidth / HomeV2Tokens.photoAspectRatio } func homeV2ReservedStage';
  expect(homePhotoStageFindings(surface, widthOnly, layout)).toEqual([
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  ]);
  const shared =
    'enum HomeV2StageReservation { case .photo, .noPhoto, .loading, .failedLoad, .offline:\n' +
    'let height = HomeV2Layout.stageHeight(\n} func homeV2ReservedStage';
  const bareLayout =
    'static func stageHeight(width: CGFloat, height: CGFloat) -> CGFloat {\n' +
    'return min(fourByFive, available)\n}';
  expect(homePhotoStageFindings(surface, shared, bareLayout)).toEqual([
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  ]);
});

it('decodes filmstrip images directly to thumbnail pixels and isolates their cache entries', () => {
  const pipeline = read('apps/ios/LogYourBody/Services/ImageCacheService.swift');
  expect(pipeline).toContain('CGImageSourceCreateThumbnailAtIndex');
  expect(pipeline).toContain('kCGImageSourceCreateThumbnailWithTransform: true');
  expect(pipeline).toContain('kCGImageSourceThumbnailMaxPixelSize: maxPixelSize');
  expect(pipeline).toContain('"thumbnail:\\(urlString)"');
  expect(pipeline).toContain('guard !Task.isCancelled else { return }');
});
