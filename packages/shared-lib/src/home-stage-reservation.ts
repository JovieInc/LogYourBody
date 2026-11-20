const sharedPresentations = 'case .photo, .noPhoto, .loading, .failedLoad, .offline:';
const aspectFormula = 'height = safeWidth / HomeV2Tokens.photoAspectRatio';
const reservationCall = 'HomeV2StageReservation.size(';
const stageWidth = 'width: geometry.size.width';

/**
 * The Home card is 4:5 for a photo, an empty day, a load, a failed load and
 * offline. HomeV2Surface asks HomeV2StageReservation for that size; the
 * reservation owns the aspect formula. An inline surface height is not a
 * substitute, because the loading and offline cards would drift.
 */
export function homeStageAspectGaps(surface: string, reservation: string): string[] {
  const gaps: string[] = [];
  const call = surface.indexOf(reservationCall);
  if (call < 0) {
    gaps.push('Home surface does not size the card with HomeV2StageReservation.size');
  } else {
    const width = surface.indexOf(stageWidth, call);
    if (width < 0 || width - call > 160) {
      gaps.push('Home surface reservation call omits width: geometry.size.width');
    }
  }

  const arm = reservation.indexOf(sharedPresentations);
  if (arm < 0) {
    gaps.push(
      'Home stage reservation does not share one 4:5 arm for photo, empty, loading, failed and offline',
    );
  } else {
    const formula = reservation.indexOf(aspectFormula, arm);
    const nextArm = reservation.indexOf('\n        case ', arm + sharedPresentations.length);
    const armEnd = nextArm < 0 ? reservation.indexOf('\n        }', arm) : nextArm;
    if (formula < 0 || (armEnd >= 0 && formula > armEnd)) {
      gaps.push('shared Home stage arm omits height = safeWidth / HomeV2Tokens.photoAspectRatio');
    }
  }
  return gaps;
}
