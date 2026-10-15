import {
  stepsHistoryDeleteEnabled,
  STEPS_HISTORY_DELETE_SERVER_FLAG,
} from './steps-history-delete';

describe('steps deletion server availability', () => {
  it.each([undefined, '', 'false', 'TRUE', '1'])('defaults off for %p', (value) => {
    expect(stepsHistoryDeleteEnabled({ [STEPS_HISTORY_DELETE_SERVER_FLAG]: value })).toBe(false);
  });
  it('enables only the explicit deployment value', () => {
    expect(stepsHistoryDeleteEnabled({ [STEPS_HISTORY_DELETE_SERVER_FLAG]: 'true' })).toBe(true);
  });
});
