'use client';

import { useEffect, useId, useRef, useState } from 'react';
import {
  createCanvasClient,
  httpCanvasClient,
  sessionCanvasPort,
  type CanvasClient,
} from '@/lib/training/mesocycle-canvas-client';
import type {
  CanvasChange,
  CanvasCommandResult,
  CanvasExercise,
  CanvasReadback,
  CanvasSession,
} from '@/lib/training/mesocycle-canvas';

type Viewport = 'ultrawide' | 'phone';

export function MesocycleCanvasBoard({
  mode = 'account',
  accountSubject,
  client,
  viewport,
  reduceMotion,
}: {
  mode?: 'fixture' | 'account';
  accountSubject?: string;
  client?: CanvasClient;
  viewport?: Viewport;
  reduceMotion?: boolean;
}) {
  const [active, setActive] = useState<CanvasClient | null>(client ?? null);
  const [readback, setReadback] = useState<CanvasReadback | null>(null);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [wide, setWide] = useState(viewport === 'ultrawide');
  const [motion, setMotion] = useState(reduceMotion === true ? 'reduced' : 'fluid');
  const focusId = useRef<string | null>(null);
  const activeRef = useRef<CanvasClient | null>(client ?? null);
  const composerId = useId();

  useEffect(() => {
    const controller = new AbortController();
    const next =
      client ??
      (mode === 'fixture'
        ? createCanvasClient(sessionCanvasPort(window.sessionStorage))
        : httpCanvasClient(
            fetch,
            accountSubject ? { subject: accountSubject, signal: controller.signal } : undefined,
          ));
    activeRef.current = next;
    setReadback(null);
    setDraft('');
    focusId.current = null;
    setBusy(false);
    setActive(next);
    return () => {
      controller.abort();
      if (activeRef.current === next) activeRef.current = null;
    };
  }, [client, mode, accountSubject]);

  useEffect(() => {
    if (viewport) {
      setWide(viewport === 'ultrawide');
      return;
    }
    const query = window.matchMedia('(min-width: 1280px)');
    const apply = () => setWide(query.matches);
    apply();
    query.addEventListener('change', apply);
    return () => query.removeEventListener('change', apply);
  }, [viewport]);

  useEffect(() => {
    if (reduceMotion !== undefined) {
      setMotion(reduceMotion ? 'reduced' : 'fluid');
      return;
    }
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    const apply = () => setMotion(query.matches ? 'reduced' : 'fluid');
    apply();
    query.addEventListener('change', apply);
    return () => query.removeEventListener('change', apply);
  }, [reduceMotion]);

  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    void active.read().then((result) => {
      if (!cancelled) setReadback(result.readback);
    });
    return () => {
      cancelled = true;
    };
  }, [active]);

  useEffect(() => {
    if (!focusId.current) return;
    const node = document.querySelector<HTMLElement>(
      `[data-instance-id="${focusId.current.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"] select`,
    );
    node?.focus();
  }, [readback]);

  async function run(work: () => Promise<CanvasCommandResult>) {
    const owner = active;
    if (!owner || activeRef.current !== owner) return;
    setBusy(true);
    try {
      const result = await work();
      if (activeRef.current === owner) setReadback(result.readback);
    } finally {
      if (activeRef.current === owner) setBusy(false);
    }
  }

  const layout = wide ? 'board' : 'stack';
  const proposal = readback?.proposal?.status === 'proposed' ? readback.proposal.proposal : null;

  return (
    <div
      className="flex min-h-screen flex-col bg-black text-white"
      data-testid="mesocycle-canvas"
      data-layout={layout}
      data-motion={motion}
    >
      <header className="border-b border-white/10 px-4 py-4">
        <p className="text-xs tracking-wide text-white/60">TRAINING PLAN</p>
        <h1 className="text-2xl font-semibold">This week</h1>
      </header>
      <div
        aria-live="polite"
        className="px-4 py-2 text-sm text-white/80"
        data-testid="canvas-narration"
      >
        {readback?.narration || 'Tell the coach the goal. Nothing is saved until you accept.'}
      </div>
      <div
        className={`flex-1 overflow-auto px-4 pb-4 ${motion === 'fluid' ? 'motion-safe:transition-all' : ''}`}
      >
        {proposal ? (
          <section
            aria-label="Proposed changes"
            className="mb-4 rounded-2xl border border-amber-300/40 p-4"
            data-testid="canvas-preview"
          >
            <h2 className="mb-2 text-sm font-medium">Review before saving</h2>
            <ul className="space-y-2">
              {proposal.changes.map((change) => (
                <PreviewRow
                  key={`${change.kind}-${change.instanceId}-${change.reason}`}
                  change={change}
                  disabled={busy}
                  onSets={(sets) =>
                    active && void run(() => active.amend(proposal.id, change.instanceId, sets))
                  }
                />
              ))}
            </ul>
            <div className="mt-3 flex gap-2">
              <button
                type="button"
                className="rounded-full bg-white px-4 py-2 text-sm font-medium text-black"
                disabled={busy}
                onClick={() => active && void run(() => active.decide(proposal.id, 'apply'))}
              >
                Accept
              </button>
              <button
                type="button"
                className="rounded-full border border-white/30 px-4 py-2 text-sm"
                disabled={busy}
                onClick={() => active && void run(() => active.decide(proposal.id, 'reject'))}
              >
                Reject
              </button>
            </div>
          </section>
        ) : null}
        <div
          className={wide ? 'flex gap-3 overflow-x-auto' : 'flex flex-col gap-3'}
          data-testid="canvas-days"
        >
          {(readback?.plan?.sessions ?? []).map((session) => (
            <DayColumn
              key={session.id}
              session={session}
              changes={proposal?.changes ?? []}
              disabled={busy || Boolean(proposal)}
              onFocusCard={(id) => {
                focusId.current = id;
              }}
              onMove={(instanceId, toDay, toSlot) =>
                active && void run(() => active.direct({ kind: 'move', instanceId, toDay, toSlot }))
              }
            />
          ))}
        </div>
        {readback?.goals.length ? (
          <section aria-label="Muscle goals" className="mt-4" data-testid="canvas-goals">
            <h2 className="mb-2 text-sm text-white/60">Muscle goals and weekly totals</h2>
            <ul className="flex flex-wrap gap-2">
              {readback.goals.map((goal) => (
                <li
                  key={goal.id}
                  className="rounded-full border border-white/15 px-3 py-1 text-sm"
                  data-goal={goal.id}
                  data-role={goal.role}
                >
                  {goal.label}: {goal.role}, {goal.weeklySets} sets
                </li>
              ))}
            </ul>
          </section>
        ) : null}
        {readback?.execution.length ? (
          <section
            aria-label="Workout readback"
            className="mt-4 text-sm text-white/70"
            data-testid="canvas-execution"
          >
            {readback.execution.map((session) => (
              <p key={session.sessionId}>
                {session.title}:{' '}
                {session.exercises
                  .map((exercise) => `${exercise.name} ${exercise.sets}x${exercise.targetReps}`)
                  .join(', ')}
              </p>
            ))}
          </section>
        ) : null}
      </div>
      <form
        className="sticky bottom-0 border-t border-white/10 bg-black px-4 py-3"
        onSubmit={(event) => {
          event.preventDefault();
          const text = draft.trim();
          if (!text || !active) return;
          setDraft('');
          void run(() => active.submit(text));
        }}
      >
        <label htmlFor={composerId} className="mb-1 block text-xs text-white/60">
          Plan message
        </label>
        <div className="flex gap-2">
          <input
            id={composerId}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            className="min-h-11 flex-1 rounded-full border border-white/20 bg-transparent px-4"
            placeholder="Prioritize upper chest and triceps"
            data-testid="canvas-composer"
          />
          <button
            type="submit"
            className="rounded-full bg-white px-4 text-sm font-medium text-black"
            disabled={busy}
          >
            Send
          </button>
        </div>
      </form>
    </div>
  );
}

function PreviewRow({
  change,
  disabled,
  onSets,
}: {
  change: CanvasChange;
  disabled: boolean;
  onSets: (sets: number) => void;
}) {
  const name = change.kind === 'replaced' ? change.toName : change.name;
  const sets = change.kind === 'updated' ? change.sets : 0;
  const summary =
    change.kind === 'added'
      ? `${change.name} added`
      : change.kind === 'moved'
        ? `${change.name} moved to ${change.toDay} ${change.toSlot}`
        : change.kind === 'replaced'
          ? `${change.fromName} replaced with ${change.toName}`
          : change.kind === 'reordered'
            ? `${change.name} reordered`
            : `${change.name} sets`;
  return (
    <li data-change={change.kind} data-instance-id={change.instanceId} className="text-sm">
      <span>
        {summary}. {change.reason}
      </span>
      {change.kind === 'updated' ? (
        <label className="ml-2">
          Sets for {name}
          <input
            aria-label={`Sets for ${name}`}
            className="ml-2 w-16 rounded border border-white/20 bg-transparent px-2"
            type="number"
            min={1}
            max={8}
            defaultValue={sets}
            disabled={disabled}
            onChange={(event) => {
              const next = Number(event.target.value);
              if (next >= 1 && next <= 8) onSets(next);
            }}
          />
        </label>
      ) : null}
    </li>
  );
}

const DAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
] as const;

function DayColumn({
  session,
  changes,
  disabled,
  onFocusCard,
  onMove,
}: {
  session: CanvasSession;
  changes: CanvasChange[];
  disabled: boolean;
  onFocusCard: (instanceId: string) => void;
  onMove: (instanceId: string, toDay: (typeof DAYS)[number], toSlot: CanvasSession['slot']) => void;
}) {
  return (
    <section
      aria-label={session.title}
      data-testid={`canvas-day-${session.day}`}
      data-session={session.id}
      className="min-w-56 rounded-2xl border border-white/10 p-3"
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        const instanceId = event.dataTransfer.getData('text/plain');
        if (instanceId) onMove(instanceId, session.day, session.slot);
      }}
    >
      <h2 className="mb-2 text-sm font-medium">{session.title}</h2>
      <ul className="space-y-2">
        {session.exercises.map((exercise) => (
          <ExerciseCard
            key={exercise.instanceId}
            exercise={exercise}
            change={changes.find((item) => item.instanceId === exercise.instanceId)?.kind}
            disabled={disabled}
            onFocus={() => onFocusCard(exercise.instanceId)}
            onMove={(day) => onMove(exercise.instanceId, day, 'single')}
          />
        ))}
      </ul>
    </section>
  );
}

function ExerciseCard({
  exercise,
  change,
  disabled,
  onFocus,
  onMove,
}: {
  exercise: CanvasExercise;
  change?: CanvasChange['kind'];
  disabled: boolean;
  onFocus: () => void;
  onMove: (day: (typeof DAYS)[number]) => void;
}) {
  const moveId = useId();
  return (
    <li>
      <article
        data-instance-id={exercise.instanceId}
        data-change={change ?? 'saved'}
        draggable={!disabled}
        onDragStart={(event) => {
          onFocus();
          event.dataTransfer.setData('text/plain', exercise.instanceId);
        }}
        className="rounded-xl bg-white/5 p-3"
      >
        <h3 className="text-sm font-medium">{exercise.name}</h3>
        <p className="text-xs text-white/70">
          {exercise.sets} sets · {exercise.targetReps} reps · {exercise.variantId} ·{' '}
          {exercise.priority}
        </p>
        <label htmlFor={moveId} className="mt-2 block text-xs text-white/60">
          Move {exercise.name}
        </label>
        <select
          id={moveId}
          aria-label={`Move ${exercise.name}`}
          className="mt-1 w-full rounded-lg border border-white/20 bg-black px-2 py-1 text-sm outline-none focus-visible:ring-2 focus-visible:ring-white"
          disabled={disabled}
          defaultValue=""
          onFocus={onFocus}
          onChange={(event) => {
            const day = DAYS.find((item) => item === event.target.value);
            if (day) onMove(day);
            event.target.value = '';
          }}
        >
          <option value="">Choose a day</option>
          {DAYS.map((day) => (
            <option key={day} value={day}>
              {day}
            </option>
          ))}
        </select>
      </article>
    </li>
  );
}
