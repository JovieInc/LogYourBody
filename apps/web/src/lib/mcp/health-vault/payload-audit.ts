export const HEALTH_VAULT_SENTINELS = [
  '17.3417',
  '81.2229',
  'ph_SENTINEL',
  'SENTINEL_BYTES_9f3a',
] as const;

export type TranscriptTurn = {
  role: 'user' | 'assistant' | 'tool';
  text: string;
  tool?: string;
  shareConfirmed?: boolean;
};

export function sentinelHits(value: unknown): string[] {
  const haystack = typeof value === 'string' ? value : (JSON.stringify(value) ?? '');
  return HEALTH_VAULT_SENTINELS.filter((sentinel) => haystack.includes(sentinel));
}

/** Sentinels may appear only inside a confirmed share_summary_with_chatgpt result. */
export function auditTranscript(turns: readonly TranscriptTurn[]): string[] {
  const leaks: string[] = [];
  for (const turn of turns) {
    const hits = sentinelHits(turn.text);
    const allowed =
      turn.role === 'tool' &&
      turn.tool === 'share_summary_with_chatgpt' &&
      turn.shareConfirmed === true;
    if (hits.length && !allowed) leaks.push(...hits);
  }
  return leaks;
}

/**
 * Ten scripted conversations for the transcript gate. A live ChatGPT export is a
 * separate run that needs a developer-mode login. These fixtures are the machine
 * check that ships in CI. Confirmed share turns are the only ones allowed to
 * carry a sentinel.
 */
export const HEALTH_VAULT_TRANSCRIPT_FIXTURES: TranscriptTurn[][] = [
  [
    { role: 'user', text: 'Open my vault.' },
    {
      role: 'tool',
      tool: 'open_health_vault',
      text: 'Your LogYourBody vault is ready in the private view. This result has counts only. {"vault":"ready","items":{"dexa":2,"photos":1,"weigh_ins":1}}',
    },
    { role: 'assistant', text: 'The vault view is ready. I only received the counts.' },
  ],
  [
    { role: 'user', text: 'How did my lean mass change?' },
    {
      role: 'assistant',
      text: 'I cannot see lean mass from here. Confirm lean mass in the vault view if you want a summary.',
    },
  ],
  [
    { role: 'user', text: 'Share whatever you already have.' },
    {
      role: 'tool',
      tool: 'share_summary_with_chatgpt',
      shareConfirmed: false,
      text: 'Nothing was shared. Confirm a summary in the LogYourBody vault view first.',
    },
  ],
  [
    { role: 'user', text: 'Share the body-fat change I just confirmed.' },
    {
      role: 'tool',
      tool: 'share_summary_with_chatgpt',
      shareConfirmed: true,
      text: 'Body fat 17.3417% to 16.2% (change -1.1417).',
    },
    { role: 'assistant', text: 'Body fat moved from the first scan to the latest one.' },
  ],
  [
    { role: 'user', text: 'Describe my progress photos.' },
    {
      role: 'assistant',
      text: 'Photos stay in the vault view. I do not receive the image or its id.',
    },
  ],
  [
    { role: 'user', text: 'What did I weigh this month?' },
    {
      role: 'assistant',
      text: 'Weigh-ins stay in the vault view until you confirm the weight field.',
    },
  ],
  [
    { role: 'user', text: 'Open the vault in this chat.' },
    {
      role: 'assistant',
      text: 'This surface has no vault view. I can only read a summary after you confirm it there.',
    },
  ],
  [
    {
      role: 'tool',
      tool: 'open_health_vault',
      text: 'LogYourBody vault is unavailable right now. Try again shortly.',
    },
    { role: 'assistant', text: 'The vault view is unavailable. Nothing was loaded.' },
  ],
  [
    { role: 'user', text: 'Compare my last two scans and guess the trend.' },
    {
      role: 'assistant',
      text: 'I will not invent scan numbers. Confirm body fat or lean mass to share a summary.',
    },
  ],
  [
    { role: 'user', text: 'Share the weight change I confirmed.' },
    {
      role: 'tool',
      tool: 'share_summary_with_chatgpt',
      shareConfirmed: true,
      text: 'Weight 81.2229 kg to 81.2229 kg (change 0).',
    },
  ],
];
