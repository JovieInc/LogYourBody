/** A product-account incarnation captured after authentication, before request awaits.
 * This is not an issuer token/session binding and must never be recaptured on retry.
 */
export type NativeAccountAdmission = Readonly<{ subject: string; ownerId: string }>;

export type NativeAccountFailure =
  'account_not_found' | 'account_changed' | 'account_admission_unavailable';

export class NativeAccountAdmissionError extends Error {
  constructor(readonly code: NativeAccountFailure) {
    super(code);
    this.name = 'NativeAccountAdmissionError';
  }
}

export function nativeAccountFailureStatus(error: unknown): number | null {
  if (!(error instanceof NativeAccountAdmissionError)) return null;
  return error.code === 'account_not_found' ? 404 : error.code === 'account_changed' ? 409 : 503;
}

export function requireNativeAccountAdmission(
  admission: NativeAccountAdmission | null,
): NativeAccountAdmission {
  if (!admission) throw new NativeAccountAdmissionError('account_not_found');
  return admission;
}

export interface NativeAccountAdmissionPort {
  capture(subject: string): Promise<NativeAccountAdmission | null>;
}
