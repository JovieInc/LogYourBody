export type ProductUserIdentity = {
  subject: string;
  phoneNumber?: string | null;
  email?: string | null;
  displayName?: string | null;
  avatarUrl?: string | null;
};

export interface UserDirectoryPort {
  recordSignIn(identity: ProductUserIdentity): Promise<void>;
}
