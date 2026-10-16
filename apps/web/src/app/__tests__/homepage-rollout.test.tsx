import { render, screen } from '@testing-library/react';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { ART_DIRECTION_V2_ENABLED: false, APP_STORE_LIVE: false },
}));
jest.mock('@/lib/flags/publicLanding.server', () => ({ readEditorialHomepageRollout: jest.fn() }));

import HomePage, { revalidate } from '../page';
import { LaunchLanding } from '../LaunchLanding';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { readEditorialHomepageRollout } from '@/lib/flags/publicLanding.server';

const flags = LANDING_FLAGS as { ART_DIRECTION_V2_ENABLED: boolean };
const readRollout = jest.mocked(readEditorialHomepageRollout);

beforeEach(() => {
  jest.clearAllMocks();
  flags.ART_DIRECTION_V2_ENABLED = false;
  readRollout.mockResolvedValue(false);
});

it('preserves the legacy page and skips Statsig when the rollback switch is off', async () => {
  render(await HomePage());
  expect(readRollout).not.toHaveBeenCalled();
  expect(screen.getByRole('heading', { name: 'What it keeps' })).toBeInTheDocument();
  expect(
    screen.queryByRole('heading', { name: 'Keep showing up. See what changes.' }),
  ).not.toBeInTheDocument();
});

it('requires both rollout switches before rendering the editorial homepage', async () => {
  flags.ART_DIRECTION_V2_ENABLED = true;
  const legacy = render(await HomePage());
  expect(screen.getByRole('heading', { name: 'What it keeps' })).toBeInTheDocument();
  legacy.unmount();
  readRollout.mockResolvedValue(true);
  render(await HomePage());
  expect(
    screen.getByRole('heading', { name: 'Keep showing up. See what changes.' }),
  ).toBeInTheDocument();
  expect(screen.getAllByRole('textbox')).toHaveLength(1);
  expect(readRollout).toHaveBeenCalledTimes(2);
  expect(revalidate).toBe(30);
});

it('honors a subsequent provider rollback without a source build', async () => {
  flags.ART_DIRECTION_V2_ENABLED = true;
  readRollout.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
  const editorial = render(await HomePage());
  expect(
    screen.getByRole('heading', { name: 'Keep showing up. See what changes.' }),
  ).toBeInTheDocument();
  editorial.unmount();
  render(await HomePage());
  expect(screen.getByRole('heading', { name: 'What it keeps' })).toBeInTheDocument();
  expect(
    screen.queryByRole('heading', { name: 'Keep showing up. See what changes.' }),
  ).not.toBeInTheDocument();
});

it('does not redesign other LaunchLanding callers through the homepage switch', () => {
  flags.ART_DIRECTION_V2_ENABLED = true;
  render(<LaunchLanding />);
  expect(screen.getByRole('heading', { name: 'What it keeps' })).toBeInTheDocument();
  expect(readRollout).not.toHaveBeenCalled();
});
