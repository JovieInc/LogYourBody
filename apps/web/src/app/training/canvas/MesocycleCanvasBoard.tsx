'use client';

import { useCallback, useEffect, useId, useRef, useState } from 'react';
import {
  canvasReadback,
  emptyJournal,
  parseJournal,
  reduceCanvas,
  type CanvasCommand,
  type CanvasDayId,
  type CanvasExercise,
  type CanvasHighlight,
  type CanvasJournal,
  type CanvasOp,
  type CanvasPlan,
  type CanvasResult,
} from '@/lib/training/mesocycle-canvas';
import styles from './mesocycle-canvas.module.css';

export const CANVAS_STORAGE_KEY = 'lyb.mesocycle-canvas.v1';

export type CanvasStorage = {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
};

type Layout = 'mobile' | 'ultrawide';

const memoryFallback = new Map<string, string>();

function browserStorage(): CanvasStorage {
  if (typeof window === 'undefined') {
    return {
      getItem: (key) => memoryFallback.get(key) ?? null,
      setItem: (key, value) => {
        memoryFallback.set(key, value);
      },
    };
  }
  return window.localStorage;
}

function describeFailure(result: CanvasResult): string {
  if (result.kind === 'unsupported_equipment') {
    return `Unsupported equipment: ${result.missing.join(', ')}. Nothing was saved.`;
  }
  if (result.kind === 'unsupported_command')
    return 'That command is not supported. Nothing was saved.';
  if (result.kind === 'invalid_operation')
    return `The edit was rejected (${result.reason}). Nothing was saved.`;
  if (result.kind === 'stale_context')
    return 'That edit is stale. The saved plan was left unchanged.';
  if (result.kind === 'nothing_to_undo') return 'Nothing to undo.';
  if (result.kind === 'nothing_to_redo') return 'Nothing to redo.';
  return `The edit was not saved (${result.kind}).`;
}

function opLabel(op: CanvasOp): string {
  if (op.kind === 'prioritize')
    return op.target === 'upper_chest' ? 'Prioritize upper chest' : 'Prioritize triceps';
  if (op.kind === 'training_days') return 'Train five days';
  if (op.kind === 'split_day') return 'Split Wednesday into AM and PM';
  if (op.kind === 'swap_variant')
    return 'Swap incline dumbbell press for Smith machine incline press';
  if (op.kind === 'declare_equipment') return `Declare ${op.item.split('_').join(' ')}`;
  if (op.kind === 'move') return `Move ${op.instanceId}`;
  if (op.kind === 'set_sets') return `Set ${op.instanceId} to ${op.sets} sets`;
  if (op.kind === 'draft') return 'Accept the coach draft';
  if (op.kind === 'undo') return 'Undo the last accepted edit';
  return 'Redo the undone edit';
}

function pendingProposal(journal: CanvasJournal) {
  return (
    [...journal.proposals].reverse().find((proposal) => proposal.status === 'proposed') ?? null
  );
}

function exerciseById(plan: CanvasPlan | null, instanceId: string): CanvasExercise | null {
  if (!plan) return null;
  for (const day of plan.days) {
    for (const session of day.sessions) {
      const found = session.exercises.find((exercise) => exercise.instanceId === instanceId);
      if (found) return found;
    }
  }
  return null;
}

function readbackText(journal: CanvasJournal): string {
  const plan = canvasReadback(journal).plan;
  if (!plan) return 'No saved plan';
  return plan.days
    .flatMap((day) =>
      day.sessions.flatMap((session) =>
        session.exercises.map(
          (exercise) =>
            `${exercise.instanceId}|${exercise.name}|${exercise.sets}|${exercise.priority}|${session.id}`,
        ),
      ),
    )
    .join('\n');
}

function nextDestination(plan: CanvasPlan, instanceId: string) {
  const index = plan.days.findIndex((day) =>
    day.sessions.some((session) =>
      session.exercises.some((exercise) => exercise.instanceId === instanceId),
    ),
  );
  if (index < 0) return null;
  const day = plan.days[(index + 1) % plan.days.length];
  const session = day?.sessions[0];
  if (!day || !session) return null;
  return { toDay: day.id, toSessionId: session.id };
}

export function MesocycleCanvasBoard({
  initialJournal = null,
  storage,
  persistKey = CANVAS_STORAGE_KEY,
  reducedMotion = false,
  layout = 'ultrawide',
  autoDraft = true,
  now = '2026-10-14T12:00:00.000Z',
}: {
  initialJournal?: CanvasJournal | null;
  storage?: CanvasStorage;
  persistKey?: string;
  reducedMotion?: boolean;
  layout?: Layout;
  autoDraft?: boolean;
  now?: string;
}) {
  const storeRef = useRef<CanvasStorage>(storage ?? browserStorage());
  storeRef.current = storage ?? storeRef.current;
  const [journal, setJournal] = useState<CanvasJournal | null>(initialJournal);
  const [ready, setReady] = useState(initialJournal != null);
  const [corrupt, setCorrupt] = useState(false);
  const [live, setLive] = useState('');
  const [draft, setDraft] = useState('');
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [setEdits, setSetEdits] = useState<Record<string, number>>({});
  const [dayIndex, setDayIndex] = useState(0);
  const draggingRef = useRef<string | null>(null);
  const [focusId, setFocusId] = useState<string | null>(null);
  const requestSeq = useRef(1);
  const journalRef = useRef(journal);
  function nextRequestId() {
    const current = journalRef.current;
    requestSeq.current += 1;
    return `req-g${current?.generation ?? 0}-p${current?.proposals.length ?? 0}-n${requestSeq.current}`;
  }
  journalRef.current = journal;
  const composerId = useId();
  const started = useRef(false);

  const persist = useCallback(
    (next: CanvasJournal, narration: string, focus?: string | null) => {
      const proposal = pendingProposal(next);
      setJournal(next);
      journalRef.current = next;
      setReady(true);
      setLive(narration);
      storeRef.current.setItem(persistKey, JSON.stringify(next));
      if (proposal) {
        setChecked(Object.fromEntries(proposal.ops.map((op) => [op.id, true])));
        setSetEdits({});
      }
      if (focus) setFocusId(focus);
    },
    [persistKey],
  );

  function applyCommand(command: CanvasCommand, focus?: string | null) {
    const current = journalRef.current;
    if (!current || corrupt) return;
    const reduced = reduceCanvas(current, command, now);
    if (reduced.result.kind === 'proposed' || reduced.result.kind === 'decided') {
      if (reduced.persist) persist(reduced.journal, reduced.result.narration, focus);
      else setLive(reduced.result.narration);
      return;
    }
    setLive(describeFailure(reduced.result));
  }

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    if (initialJournal) {
      storeRef.current.setItem(persistKey, JSON.stringify(initialJournal));
      return;
    }
    const raw = storeRef.current.getItem(persistKey);
    if (raw == null || raw.trim() === '') {
      const blank = emptyJournal();
      if (!autoDraft) {
        setJournal(blank);
        setReady(true);
        return;
      }
      const reduced = reduceCanvas(
        blank,
        {
          type: 'propose',
          requestId: 'draft-initial',
          expectedGeneration: 0,
          baseRevisionId: null,
          source: 'chat',
          text: 'Build a hypertrophy plan',
        },
        now,
      );
      if (reduced.persist && reduced.result.kind === 'proposed') {
        persist(reduced.journal, reduced.result.narration);
      } else {
        setJournal(blank);
        setReady(true);
        setLive(
          reduced.result.kind === 'proposed'
            ? reduced.result.narration
            : describeFailure(reduced.result),
        );
      }
      return;
    }
    try {
      const parsed = parseJournal(JSON.parse(raw));
      if (!parsed) {
        setCorrupt(true);
        setReady(true);
        setLive('This plan could not be read. Nothing was changed.');
        return;
      }
      setJournal(parsed);
      const proposal = pendingProposal(parsed);
      if (proposal) setChecked(Object.fromEntries(proposal.ops.map((op) => [op.id, true])));
      setReady(true);
    } catch {
      setCorrupt(true);
      setReady(true);
      setLive('This plan could not be read. Nothing was changed.');
    }
  }, [autoDraft, initialJournal, now, persist, persistKey]);

  useEffect(() => {
    if (!focusId) return;
    const escaped =
      typeof CSS !== 'undefined' && typeof CSS.escape === 'function'
        ? CSS.escape(focusId)
        : focusId.replace(/"/g, '');
    document.querySelector<HTMLElement>(`[data-focus-exercise="${escaped}"]`)?.focus();
  }, [focusId, journal]);

  const pending = journal ? pendingProposal(journal) : null;
  const shown = pending?.preview ?? (journal ? canvasReadback(journal).plan : null);
  const highlights = new Map<string, CanvasHighlight>(
    (pending?.highlights ?? []).map((highlight) => [highlight.instanceId, highlight]),
  );
  const locked = Boolean(pending) || corrupt || !ready;

  function submit(source: 'chat' | 'voice') {
    const current = journalRef.current;
    const text = draft.trim();
    if (!current || locked || !text) return;
    applyCommand({
      type: 'propose',
      requestId: nextRequestId(),
      expectedGeneration: current.generation,
      baseRevisionId: canvasReadback(current).revisionId,
      source,
      text,
    });
    setDraft('');
  }

  function proposeMove(instanceId: string, toDay: CanvasDayId, toSessionId: string) {
    const current = journalRef.current;
    if (!current || locked) return;
    applyCommand(
      {
        type: 'propose',
        requestId: nextRequestId(),
        expectedGeneration: current.generation,
        baseRevisionId: canvasReadback(current).revisionId,
        source: 'direct',
        ops: [
          {
            id: `drag-${instanceId}-${requestSeq.current}`,
            kind: 'move',
            instanceId,
            toDay,
            toSessionId,
            toIndex: 0,
          },
        ],
      },
      instanceId,
    );
  }

  function accept() {
    const current = journalRef.current;
    const proposal = current ? pendingProposal(current) : null;
    if (!current || !proposal) return;
    const acceptedOpIds = proposal.ops.filter((op) => checked[op.id] !== false).map((op) => op.id);
    const edits = Object.entries(setEdits).flatMap(([instanceId, sets]) => {
      const exercise = exerciseById(proposal.preview, instanceId);
      return exercise && exercise.sets !== sets ? [{ instanceId, sets }] : [];
    });
    const command: CanvasCommand = {
      type: 'decide',
      requestId: nextRequestId(),
      proposalId: proposal.id,
      expectedGeneration: current.generation,
      decision: 'apply',
      acceptedOpIds,
    };
    if (edits.length > 0 && command.type === 'decide') command.setEdits = edits;
    const moved = proposal.highlights.find(
      (highlight) => highlight.change === 'moved' || highlight.change === 'replaced',
    );
    applyCommand(command, moved?.instanceId ?? focusId);
  }

  function reject() {
    const current = journalRef.current;
    const proposal = current ? pendingProposal(current) : null;
    if (!current || !proposal) return;
    applyCommand({
      type: 'decide',
      requestId: nextRequestId(),
      proposalId: proposal.id,
      expectedGeneration: current.generation,
      decision: 'reject',
    });
  }

  const activeDay = shown?.days[Math.min(dayIndex, Math.max((shown?.days.length ?? 1) - 1, 0))]?.id;

  return (
    <main
      className={`${styles.board} ${layout === 'mobile' ? styles.mobile : ''} ${reducedMotion ? styles.reduce : ''}`}
      data-layout={layout}
      data-reduced-motion={reducedMotion ? 'true' : 'false'}
    >
      <p
        className={styles.composer}
        style={{ position: 'static' }}
        aria-live="polite"
        data-testid="canvas-live"
      >
        {live}
      </p>
      <p data-testid="canvas-readback">{journal ? readbackText(journal) : 'No saved plan'}</p>
      {!ready ? <p data-testid="canvas-loading">Loading the saved plan.</p> : null}
      {corrupt ? (
        <p role="alert" data-testid="canvas-corrupt">
          This plan could not be read. Nothing was changed.
        </p>
      ) : null}
      {shown ? (
        <>
          <ul aria-label="Muscle goals">
            {shown.goals.map((goal) => (
              <li key={goal.id} data-goal={goal.id} data-role={goal.role}>
                {goal.label}: {goal.role}, {goal.weeklySets} weekly sets
              </li>
            ))}
          </ul>
          <ul aria-label="Weekly totals">
            {Object.entries(shown.weeklyTotals)
              .filter(([, sets]) => sets > 0)
              .map(([muscle, sets]) => (
                <li key={muscle}>
                  {muscle}: {sets}
                </li>
              ))}
          </ul>
        </>
      ) : null}
      {pending ? (
        <section aria-label="Plan preview">
          <p>Preview. The saved plan changes only when you accept.</p>
          <p data-testid="canvas-preview-source">{pending.source}</p>
          {pending.ops.map((op) => (
            <label key={op.id}>
              <input
                type="checkbox"
                checked={checked[op.id] !== false}
                onChange={(event) =>
                  setChecked((current) => ({ ...current, [op.id]: event.target.checked }))
                }
              />
              {opLabel(op)}
            </label>
          ))}
          <button type="button" onClick={accept}>
            Accept
          </button>
          <button type="button" onClick={reject}>
            Reject
          </button>
        </section>
      ) : null}
      <div className={styles.pager}>
        <button type="button" onClick={() => setDayIndex((index) => Math.max(0, index - 1))}>
          Previous day
        </button>
        <button
          type="button"
          onClick={() => setDayIndex((index) => Math.min((shown?.days.length ?? 1) - 1, index + 1))}
        >
          Next day
        </button>
      </div>
      <div className={styles.columns}>
        {shown?.days.map((day) => (
          <section
            key={day.id}
            className={styles.day}
            data-active={day.id === activeDay ? 'true' : 'false'}
            aria-label={day.label}
          >
            <h2>{day.label}</h2>
            {day.sessions.map((session) => (
              <div
                key={session.id}
                className={styles.session}
                data-testid={`session-${session.id}`}
                onDragOver={(event) => event.preventDefault()}
                onDrop={(event) => {
                  event.preventDefault();
                  const instanceId =
                    draggingRef.current || event.dataTransfer?.getData('text/plain');
                  draggingRef.current = null;
                  if (instanceId) proposeMove(instanceId, day.id, session.id);
                }}
              >
                <h3>{session.title}</h3>
                {session.exercises.map((exercise) => {
                  const change = highlights.get(exercise.instanceId)?.change;
                  return (
                    <article
                      key={exercise.instanceId}
                      className={`${styles.card} ${change ? styles[change] : ''}`}
                      data-instance-id={exercise.instanceId}
                      data-variant={exercise.variantId}
                      data-priority={exercise.priority}
                      data-sets={exercise.sets}
                      data-change={change ?? 'none'}
                      draggable={!locked}
                      onDragStart={(event) => {
                        draggingRef.current = exercise.instanceId;
                        event.dataTransfer?.setData('text/plain', exercise.instanceId);
                      }}
                    >
                      <h4>
                        <button
                          type="button"
                          className={styles.name}
                          tabIndex={-1}
                          data-focus-exercise={exercise.instanceId}
                        >
                          {exercise.name}
                        </button>
                      </h4>
                      <p>
                        {exercise.sets} sets · {exercise.repRange.min}-{exercise.repRange.max} reps
                        · {exercise.priority}
                      </p>
                      <p>{highlights.get(exercise.instanceId)?.reason}</p>
                      {pending ? (
                        <label>
                          Sets for {exercise.name}
                          <input
                            aria-label={`Sets for ${exercise.name}`}
                            type="number"
                            min={1}
                            max={6}
                            value={setEdits[exercise.instanceId] ?? exercise.sets}
                            onChange={(event) =>
                              setSetEdits((current) => ({
                                ...current,
                                [exercise.instanceId]: Number(event.target.value),
                              }))
                            }
                          />
                        </label>
                      ) : null}
                      <button
                        type="button"
                        disabled={locked}
                        onClick={() => {
                          const destination = shown
                            ? nextDestination(shown, exercise.instanceId)
                            : null;
                          if (destination)
                            proposeMove(
                              exercise.instanceId,
                              destination.toDay,
                              destination.toSessionId,
                            );
                        }}
                      >
                        Move {exercise.name} to the next day
                      </button>
                    </article>
                  );
                })}
              </div>
            ))}
          </section>
        ))}
      </div>
      <form
        className={styles.composer}
        onSubmit={(event) => {
          event.preventDefault();
          submit('chat');
        }}
      >
        <label htmlFor={composerId}>Plan message</label>
        <textarea
          id={composerId}
          value={draft}
          disabled={locked}
          onChange={(event) => setDraft(event.target.value)}
        />
        <button type="submit" disabled={locked || draft.trim() === ''}>
          Send
        </button>
        <button
          type="button"
          disabled={locked || draft.trim() === ''}
          onClick={() => submit('voice')}
        >
          Send voice
        </button>
      </form>
    </main>
  );
}
