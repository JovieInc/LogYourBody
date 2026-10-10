export interface WaitlistEntryInput {
  email: string;
  source: string;
}

export interface WaitlistStoragePort {
  accept(entry: WaitlistEntryInput): Promise<{ created: boolean }>;
  countRegistrations(window: { from: string; to: string }): Promise<{
    count: number;
    observedAt: string;
  }>;
}
