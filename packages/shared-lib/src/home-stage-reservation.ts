// Source contracts follow HomeV2StageReservation, not an inline call-site formula.
// Photo, empty, loading, failed and offline Home cards share one budget. That
// budget is 4:5 through HomeV2Layout.stageHeight when the column can hold it,
// and shorter only so the number and check-in stay on a short screen.

const RESERVATION_START = 'enum HomeV2StageReservation';
const RESERVATION_END = 'func homeV2ReservedStage';
const LAYOUT_START = 'static func stageHeight';
const LAYOUT_END = 'enum HomeV2EditorialPolicy';

function sliceBetween(source: string, startMark: string, endMark: string): string {
  const start = source.indexOf(startMark);
  if (start < 0) return '';
  const end = source.indexOf(endMark, start + startMark.length);
  return source.slice(start, end > start ? end : undefined);
}

export function homePhotoStageFindings(
  surface: string,
  reservationSource: string,
  layoutSource: string,
): string[] {
  const findings: string[] = [];
  const stage = sliceBetween(reservationSource, RESERVATION_START, RESERVATION_END);
  const budget = sliceBetween(layoutSource, LAYOUT_START, LAYOUT_END);
  if (!surface.includes('HomeV2StageReservation.size(')) {
    findings.push('HomeV2Surface sizes the timeline outside HomeV2StageReservation');
  }
  if (!surface.includes('hasPhoto ? .photo : .noPhoto')) {
    findings.push('HomeV2Surface omits the photo presentation for a usable photo');
  }
  if (!stage.includes('case .photo, .noPhoto, .loading, .failedLoad, .offline:')) {
    findings.push('HomeV2StageReservation does not keep a photo on the shared frame');
  }
  const sharesBudget = stage.includes('HomeV2Layout.stageHeight(');
  const keepsRatio =
    budget.includes('width / HomeV2Tokens.photoAspectRatio') &&
    budget.includes('return min(fourByFive, available)');
  if (!sharesBudget || !keepsRatio) {
    findings.push('HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio');
  }
  return findings;
}

export function estimateOnPhotoStageFindings(hero: string): string[] {
  const findings: string[] = [];
  const reserved = hero.indexOf('.homeV2ReservedStage(');
  const overlay = hero.indexOf('.overlay { estimateCanvas }');
  if (reserved < 0 || overlay < 0 || overlay < reserved) {
    findings.push('estimate canvas sits outside the reserved Home photo stage');
  }
  if (!hero.includes('.homeV2ReservedStage(size)') || hero.includes('homeV2ReservedStage(width:')) {
    findings.push('estimate stage omits the reserved photo size');
  }
  return findings;
}
