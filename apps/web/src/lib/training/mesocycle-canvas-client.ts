import {
  amendCanvasProposal,
  canvasLedgerSchema,
  decideCanvasProposal,
  interpretPlanUtterance,
  proposeCanvasEdit,
  readCanvas,
  readCanvasLedger,
  type CanvasCommandResult,
  type CanvasLedgerPort,
  type PlanOperation,
} from './mesocycle-canvas';

export type CanvasClient = {
  read(): Promise<CanvasCommandResult>;
  submit(transcript: string): Promise<CanvasCommandResult>;
  direct(operation: PlanOperation): Promise<CanvasCommandResult>;
  decide(proposalId: string, decision: 'apply' | 'reject'): Promise<CanvasCommandResult>;
  amend(proposalId: string, instanceId: string, sets: number): Promise<CanvasCommandResult>;
};

const STORAGE_KEY = 'lyb.mesocycle-canvas.v1';

export function sessionCanvasPort(storage: Pick<Storage, 'getItem' | 'setItem'>): CanvasLedgerPort {
  return {
    async load(_subject) {
      const raw = storage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = canvasLedgerSchema.safeParse(JSON.parse(raw));
      if (!parsed.success) throw new Error('ledger_invalid');
      return parsed.data;
    },
    async save(subject, expectedWrite, ledger) {
      const current = await this.load(subject);
      if ((current?.write ?? null) !== expectedWrite) return { kind: 'stale' };
      storage.setItem(STORAGE_KEY, JSON.stringify(ledger));
      return { kind: 'saved' };
    },
  };
}

function nextRequestId(): string {
  if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
  const tail = `${Date.now().toString(16)}${Math.floor(Math.random() * 0xffffffff).toString(16)}`
    .padStart(12, '0')
    .slice(-12);
  return `00000000-0000-4000-8000-${tail}`;
}

/** Browser and tests share this adapter. It never applies an operation by itself. */
export function createCanvasClient(port: CanvasLedgerPort, subject = 'local'): CanvasClient {
  const now = () => new Date().toISOString();
  let write: number | null = null;

  function remember(result: CanvasCommandResult): CanvasCommandResult {
    write = result.readback.write;
    return result;
  }

  async function propose(operation: PlanOperation): Promise<CanvasCommandResult> {
    return remember(
      await proposeCanvasEdit(port, subject, {
        requestId: nextRequestId(),
        expectedWrite: write,
        operation,
        now: now(),
      }),
    );
  }

  return {
    async read() {
      try {
        return remember(await readCanvas(port, subject));
      } catch {
        return {
          kind: 'ledger_invalid',
          readback: readCanvasLedger(null, 'The saved plan could not be read.'),
        };
      }
    },
    async submit(transcript) {
      const operation = interpretPlanUtterance(transcript);
      if (!operation) {
        const current = await readCanvas(port, subject);
        return {
          kind: 'unsupported_or_invalid_intent',
          readback: {
            ...current.readback,
            narration: 'That message is not a plan edit. Nothing was saved.',
          },
        };
      }
      return propose(operation);
    },
    direct: propose,
    async decide(proposalId, decision) {
      return remember(
        await decideCanvasProposal(port, subject, {
          requestId: nextRequestId(),
          proposalId,
          decision,
          expectedWrite: write,
          now: now(),
        }),
      );
    },
    async amend(proposalId, instanceId, sets) {
      return remember(
        await amendCanvasProposal(port, subject, {
          proposalId,
          instanceId,
          sets,
          expectedWrite: write,
        }),
      );
    },
  };
}

export function httpCanvasClient(fetchImpl: typeof fetch = fetch): CanvasClient {
  let write: number | null = null;
  async function send(body: Record<string, unknown>): Promise<CanvasCommandResult> {
    const empty = readCanvasLedger(null, 'The plan could not be loaded.');
    try {
      const response = await fetchImpl('/api/auth/mobile/training/v1/canvas', {
        method: 'POST',
        headers: { accept: 'application/json', 'content-type': 'application/json' },
        body: JSON.stringify({ ...body, expectedWrite: write }),
      });
      const payload = (await response.json()) as Partial<CanvasCommandResult> & { error?: string };
      if (payload.readback && typeof payload.kind === 'string') {
        const result = payload as CanvasCommandResult;
        write = result.readback.write;
        return result;
      }
      return {
        kind: payload.error === 'stale_context' ? 'stale_context' : 'missed_update',
        readback: empty,
      };
    } catch {
      return { kind: 'missed_update', readback: empty };
    }
  }
  return {
    read: () => send({ action: 'read' }),
    submit: (transcript) => send({ action: 'submit', transcript }),
    direct: (operation) => send({ action: 'propose', operation }),
    decide: (proposalId, decision) => send({ action: 'decide', proposalId, decision }),
    amend: (proposalId, instanceId, sets) =>
      send({ action: 'amend', proposalId, instanceId, sets }),
  };
}
