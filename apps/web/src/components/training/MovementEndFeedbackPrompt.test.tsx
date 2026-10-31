import { fireEvent, render, screen, within } from '@testing-library/react';
import {
  MovementEndFeedbackPrompt,
  type MovementEndFeedbackPayload,
} from './MovementEndFeedbackPrompt';

const LABELS = [
  ['target-muscle effort', 'targetMuscleEffort'],
  ['back/trunk fatigue', 'trunkFatigue'],
  ['stability', 'stability'],
  ['usable ROM limited', 'romRestriction'],
] as const;

const BANNED_CONTROLS = [/joint pain/i, /\bpump\b/i, /soreness/i, /workload/i];
const DIAGNOSTIC_OR_INJURY_PREVENTION =
  /\bdiagnos\w*\b|\binjur(?:y|ies)\b|\binjury[- ]prevention\b|\bprevent\w*\s+injur\w*\b/i;

function group(name: string) {
  return screen.getByRole('group', { name });
}

function prompt(setNumber: number, setsInMovement: number, onSubmit = jest.fn()) {
  return render(
    <MovementEndFeedbackPrompt
      setNumber={setNumber}
      setsInMovement={setsInMovement}
      onSubmit={onSubmit}
    />,
  );
}

describe('movement end feedback prompt', () => {
  it('mounts at movement end and stays unmounted after a set', () => {
    const end = prompt(3, 3);
    expect(screen.getByRole('form', { name: 'Optional movement notes' })).toBeInTheDocument();
    end.unmount();

    prompt(1, 3);
    expect(screen.queryByRole('form', { name: 'Optional movement notes' })).not.toBeInTheDocument();
    prompt(2, 3);
    expect(screen.queryByRole('form', { name: 'Optional movement notes' })).not.toBeInTheDocument();
  });

  it('submits each dimension on its own and omits a skipped dimension instead of writing zero', () => {
    LABELS.forEach(([label, key], index) => {
      const onSubmit = jest.fn();
      const view = prompt(2, 2, onSubmit);
      fireEvent.click(within(group(label)).getByRole('radio', { name: String(index + 3) }));
      fireEvent.click(screen.getByRole('button', { name: 'Save movement notes' }));
      const payload = onSubmit.mock.calls[0][0] as MovementEndFeedbackPayload;
      expect(payload).toEqual({ [key]: index + 3 });
      for (const [, other] of LABELS) {
        if (other !== key) {
          expect(payload).not.toHaveProperty(other);
          expect(payload[other]).not.toBe(0);
        }
      }
      view.unmount();
    });

    const onSubmit = jest.fn();
    const view = prompt(1, 1, onSubmit);
    const effort = group('target-muscle effort');
    fireEvent.click(within(effort).getByRole('radio', { name: '0' }));
    fireEvent.click(within(effort).getByRole('radio', { name: 'Skip' }));
    fireEvent.click(within(group('stability')).getByRole('radio', { name: '0' }));
    fireEvent.click(screen.getByRole('button', { name: 'Save movement notes' }));
    const payload = onSubmit.mock.calls[0][0] as MovementEndFeedbackPayload;
    expect(payload).toEqual({ stability: 0 });
    expect(payload).not.toHaveProperty('targetMuscleEffort');
    expect(payload.targetMuscleEffort).not.toBe(0);
    view.unmount();
  });

  it('renders no joint-pain, pump, soreness, or workload control', () => {
    prompt(4, 4);
    const text = document.body.textContent ?? '';
    for (const pattern of BANNED_CONTROLS) {
      expect(text).not.toMatch(pattern);
      expect(screen.queryByRole('group', { name: pattern })).not.toBeInTheDocument();
    }
    expect(screen.getAllByRole('group')).toHaveLength(LABELS.length);
  });

  it('locks the labels and rejects diagnostic or injury-prevention wording', () => {
    prompt(1, 1);
    const labels = screen
      .getAllByRole('group')
      .map((element) => element.querySelector('legend')?.textContent);
    const rendered = (
      screen.getByRole('form', { name: 'Optional movement notes' }).textContent ?? ''
    )
      .replace(/\s+/g, ' ')
      .trim();
    expect(labels).toMatchInlineSnapshot(`
[
  "target-muscle effort",
  "back/trunk fatigue",
  "stability",
  "usable ROM limited",
]
`);
    expect(rendered).toMatchInlineSnapshot(
      `"Optional. Choose 0 to 10, or skip. A skip is left out.target-muscle effortSkip012345678910back/trunk fatigueSkip012345678910stabilitySkip012345678910usable ROM limitedSkip012345678910Save movement notes"`,
    );
    expect(rendered).not.toMatch(DIAGNOSTIC_OR_INJURY_PREVENTION);
    expect(labels.join('\n')).not.toMatch(DIAGNOSTIC_OR_INJURY_PREVENTION);
  });
});
