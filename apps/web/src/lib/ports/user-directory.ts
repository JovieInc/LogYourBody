export type ProductUserIdentity = {
  subject: string;
  phoneNumber?: string | null;
  email?: string | null;
  displayName?: string | null;
  avatarUrl?: string | null;
};

export type ProductUserRecord = ProductUserIdentity & {
  profileData: Record<string, unknown>;
  onboardingCompletedAt?: Date | null;
  legalAcceptedAt?: Date | null;
  termsVersion?: string | null;
  privacyVersion?: string | null;
};

export type ProductProfileUpdate = {
  profileData: Record<string, unknown>;
  displayName?: string | null;
  onboardingCompleted?: boolean;
  acceptLegal?: boolean;
  termsVersion?: string;
  privacyVersion?: string;
};

export interface UserDirectoryPort {
  recordSignIn(identity: ProductUserIdentity): Promise<void>;
  getUser(subject: string): Promise<ProductUserRecord | null>;
  updateProfile(subject: string, update: ProductProfileUpdate): Promise<ProductUserRecord>;
  deleteUser(subject: string): Promise<void>;
}
