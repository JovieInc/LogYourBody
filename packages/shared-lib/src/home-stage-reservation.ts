// Source contracts follow HomeV2StageReservation, not an inline call-site formula.
// Photo, empty, loading, failed and offline Home cards share that one 4:5 frame.

const RESERVATION_START = 'enum HomeV2StageReservation';
const RESERVATION_END = 'func homeV2ReservedStage';

function reservation(states: string): string {
  const start = states.indexOf(RESERVATION_START);
  const end = states.indexOf(RESERVATION_END);
  return start >= 0 && end > start ? states.slice(start, end) : '';
}

export function homePhotoStageFindings(surface: string, states: string): string[] {
  const findings: string[] = [];
  const stage = reservation(states);
  if (!surface.includes('HomeV2StageReservation.size(')) {
    findings.push('HomeV2Surface sizes the timeline outside HomeV2StageReservation');
  }
  if (!surface.includes('hasPhoto ? .photo : .noPhoto')) {
    findings.push('HomeV2Surface omits the photo presentation for a usable photo');
  }
  if (!stage.includes('case .photo, .noPhoto, .loading, .failedLoad, .offline:')) {
    findings.push('HomeV2StageReservation does not keep a photo on the shared frame');
  }
  if (!stage.includes('height = safeWidth / HomeV2Tokens.photoAspectRatio')) {
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
  if (!hero.includes('? .photo : .noPhoto')) {
    findings.push('estimate stage omits the photo presentation');
  }
  return findings;
}
