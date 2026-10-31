'use client';

import { useId, useRef, useState } from 'react';
import type { AlternativeOption, AlternativeSuggestions } from '@/lib/training/alternatives';
import type { DeloadState } from '@/lib/training/types';

const SUPPORT_REASON = 'Support may reduce trunk demand; it does not mean zero spinal load.';
const REASON_TEXT = {
  supported_exercise_previously_tolerated: SUPPORT_REASON,
  supported_setup_previously_tolerated: SUPPORT_REASON,
  supported_exercise_trial: `Supported exercise to try. ${SUPPORT_REASON}`,
  supported_setup_trial: `Supported setup to try. ${SUPPORT_REASON}`,
  blocked_rom_or_clearance:
    'This floor setup is withheld because range of motion or clearance is blocked.',
  missing_station: 'This station is hidden because it is not available at your active gym.',
  belt_does_not_clear_symptoms: 'A belt does not clear persistent symptoms.',
} as const satisfies Record<AlternativeOption['reason'], string> & Record<string, string>;

type ConstraintReason = Exclude<keyof typeof REASON_TEXT, AlternativeOption['reason']>;

type Props = {
  /** Supplied by the caller's existing training feature gate; defaults off. */
  enabled?: boolean;
  /** Account/session/revision identity of the reviewed selector result. */
  reviewId: string;
  currentExercise: { id: string; name: string };
  suggestions: AlternativeSuggestions;
  variantNames: Readonly<Record<string, string>>;
  painPolicy: Pick<DeloadState, 'action' | 'explanation'>;
  /** Upstream constraint outcomes, never inferred from symptoms or inventory here. */
  reasonCodes?: readonly ConstraintReason[];
  /** Persist this exact variant through the existing swap API. Resolve only on success;
   * the caller owns authoritative prescription readback and rejects failed receipts. */
  onApprove: (variantId: string) => Promise<void>;
  onReject?: () => void;
};

/** Presentation only: eligibility, pain decisions and prescriptions belong to the engine. */
export function ExerciseSwapApproval(props: Props) {
  if (!props.enabled) return null;

  return (
    <section
      aria-label="Review exercise swap"
      className="space-y-4 rounded-2xl border border-white/10 bg-black p-4 text-white"
    >
      {props.painPolicy.action === 'pause_session' ? (
        <p>{props.painPolicy.explanation}</p>
      ) : (
        <SwapReview key={props.reviewId} {...props} />
      )}
    </section>
  );
}

function SwapReview({
  currentExercise,
  suggestions,
  variantNames,
  reasonCodes = [],
  onApprove,
  onReject,
}: Props) {
  const groupId = useId();
  const saving = useRef(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [phase, setPhase] = useState<'review' | 'saving' | 'saved' | 'rejected'>('review');
  const [error, setError] = useState<string | null>(null);
  const candidates =
    suggestions.status === 'suggested'
      ? [suggestions.differentExercise, suggestions.sameExerciseSetup].filter(
          (option): option is AlternativeOption => option !== null,
        )
      : [];
  const selected = candidates.find((option) => option.variantId === selectedId);

  async function approve() {
    if (!selected || saving.current || phase !== 'review') return;
    saving.current = true;
    setPhase('saving');
    setError(null);
    try {
      await onApprove(selected.variantId);
      setPhase('saved');
    } catch {
      setError('The swap could not be saved. Your current exercise is unchanged.');
      setPhase('review');
    } finally {
      saving.current = false;
    }
  }

  if (phase === 'saved') return <p>Swap saved.</p>;
  if (phase === 'rejected') return <p>Keeping {currentExercise.name}.</p>;

  return (
    <>
      <h2 className="text-sm font-medium">Review before saving</h2>
      <p className="text-sm">Current exercise: {currentExercise.name}</p>
      {candidates.length ? (
        <fieldset className="space-y-3" disabled={phase === 'saving'}>
          <legend className="mb-2 text-sm text-white/70">Choose an alternative</legend>
          {candidates.map((option) => {
            const reasonId = `${groupId}-${option.variantId}-reason`;
            return (
              <div key={option.variantId} className="space-y-1">
                <label className="flex min-h-11 items-center gap-2 text-sm">
                  <input
                    type="radio"
                    name={groupId}
                    aria-describedby={reasonId}
                    checked={selectedId === option.variantId}
                    onChange={() => setSelectedId(option.variantId)}
                  />
                  {variantNames[option.variantId] ?? option.variantId}
                </label>
                <Reason code={option.reason} id={reasonId} />
              </div>
            );
          })}
        </fieldset>
      ) : (
        <p className="text-sm text-white/70">
          {suggestions.status === 'not_enough_evidence'
            ? 'There is not enough evidence to suggest a swap. Keep your current exercise.'
            : 'No eligible alternative was returned. Keep your current exercise.'}
        </p>
      )}
      {reasonCodes.map((code) => (
        <Reason key={code} code={code} />
      ))}
      {error ? (
        <p role="alert" className="text-sm">
          {error}
        </p>
      ) : null}
      {candidates.length ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            className="min-h-11 rounded-full bg-white px-4 py-2 text-sm font-medium text-black"
            disabled={!selected || phase === 'saving'}
            onClick={() => void approve()}
          >
            {phase === 'saving' ? 'Saving swap…' : 'Approve swap'}
          </button>
          <button
            type="button"
            className="min-h-11 rounded-full border border-white/30 px-4 py-2 text-sm"
            disabled={phase === 'saving'}
            onClick={() => {
              if (saving.current) return;
              setPhase('rejected');
              onReject?.();
            }}
          >
            Keep current exercise
          </button>
        </div>
      ) : null}
    </>
  );
}

function Reason({ code, id }: { code: keyof typeof REASON_TEXT; id?: string }) {
  return (
    <p id={id} data-reason-code={code} className="text-sm text-white/70">
      {REASON_TEXT[code]}
    </p>
  );
}
