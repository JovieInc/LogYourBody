export interface WaitlistEntryInput {
  email: string;
  source: string;
}

export interface WaitlistStoragePort {
  accept(entry: WaitlistEntryInput): Promise<void>;
}
