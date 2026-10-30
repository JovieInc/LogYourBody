'use client';

import { useState } from 'react';

/** Optional 0–10 reports collected once, at the end of a movement. */
export const MOVEMENT_END_FEEDBACK_CONTROLS = [
  { key: 'targetMuscleEffort', label: 'target-muscle effort' },
  { key: 'trunkFatigue', label: 'back/trunk fatigue' },
  { key: 'stability', label: 'stability' },
  { key: 'romRestriction', label: 'usable ROM limited' },
] as const;

export type MovementEndDimension = (typeof MOVEMENT_END_FEEDBACK_CONTROLS)[number]['key'];

/** Present keys were chosen. A skipped control is absent, including when the user did not choose zero. */
export type MovementEndFeedbackPayload = Partial<Record<MovementEndDimension, number>>;

const SCORES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] as const;

type Draft = Partial<Record<MovementEndDimension, number>>;

export function isMovementEnd(setNumber: number, setsInMovement: number): boolean {
  return setNumber >= 1 && setNumber === setsInMovement;
}

export function movementEndFeedbackPayload(draft: Draft): MovementEndFeedbackPayload {
  const payload: MovementEndFeedbackPayload = {};
  for (const { key } of MOVEMENT_END_FEEDBACK_CONTROLS) {
    const value = draft[key];
    if (value !== undefined) payload[key] = value;
  }
  return payload;
}

export function MovementEndFeedbackPrompt({
  setNumber,
  setsInMovement,
  onSubmit,
}: {
  setNumber: number;
  setsInMovement: number;
  onSubmit: (payload: MovementEndFeedbackPayload) => void;
}) {
  if (!isMovementEnd(setNumber, setsInMovement)) return null;
  return <MovementEndFeedbackForm onSubmit={onSubmit} />;
}

function MovementEndFeedbackForm({
  onSubmit,
}: {
  onSubmit: (payload: MovementEndFeedbackPayload) => void;
}) {
  const [draft, setDraft] = useState<Draft>({});

  function choose(key: MovementEndDimension, value: number | undefined) {
    setDraft((current) => {
      const next = { ...current };
      if (value === undefined) delete next[key];
      else next[key] = value;
      return next;
    });
  }

  return (
    <form
      aria-label="Optional movement notes"
      className="space-y-4 rounded-2xl border border-white/10 bg-black p-4 text-white"
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit(movementEndFeedbackPayload(draft));
      }}
    >
      <p className="text-sm text-white/70">
        Optional. Choose 0 to 10, or skip. A skip is left out.
      </p>
      {MOVEMENT_END_FEEDBACK_CONTROLS.map(({ key, label }) => (
        <fieldset key={key} className="space-y-2">
          <legend className="text-sm font-medium">{label}</legend>
          <div className="flex flex-wrap gap-2">
            <ScaleChoice
              name={key}
              label="Skip"
              checked={draft[key] === undefined}
              onChoose={() => choose(key, undefined)}
            />
            {SCORES.map((score) => (
              <ScaleChoice
                key={score}
                name={key}
                label={String(score)}
                checked={draft[key] === score}
                onChoose={() => choose(key, score)}
              />
            ))}
          </div>
        </fieldset>
      ))}
      <button type="submit" className="rounded-full border border-white/20 px-4 py-2 text-sm">
        Save movement notes
      </button>
    </form>
  );
}

function ScaleChoice({
  name,
  label,
  checked,
  onChoose,
}: {
  name: string;
  label: string;
  checked: boolean;
  onChoose: () => void;
}) {
  return (
    <label className="inline-flex items-center gap-1 text-sm">
      <input type="radio" name={name} checked={checked} onChange={onChoose} />
      {label}
    </label>
  );
}
