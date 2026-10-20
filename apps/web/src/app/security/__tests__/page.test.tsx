import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { logYourBody } from '@jovieinc/product-registry';
import SecurityPage from '../page';

jest.mock('@/components/Header', () => ({ Header: () => <header /> }));
jest.mock('@/components/Footer', () => ({ Footer: () => <footer /> }));

describe('security reporting handoff', () => {
  it('opens the verified private destination without pretending to accept a report', () => {
    jest.useFakeTimers();
    try {
      const { container } = render(<SecurityPage />);
      const report = screen.getByRole('link', { name: 'Report privately on GitHub' });
      expect(report).toHaveAttribute('href', `${logYourBody.links.github}/security/advisories/new`);
      expect(screen.getByText(/sign in to GitHub/)).toBeVisible();
      expect(screen.getByText(/Opening the link below does not submit a report/)).toBeVisible();
      // Prevent navigation in the isolated test; never send a vulnerability report.
      report.addEventListener('click', (event) => event.preventDefault());
      fireEvent.click(report);
      act(() => {
        jest.advanceTimersByTime(3000);
      });
      expect(container.querySelector('form')).toBeNull();
      expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
      expect(
        screen.queryByText(/report submitted|report id|we have received|investigate it promptly/i),
      ).not.toBeInTheDocument();
      expect(jest.getTimerCount()).toBe(0);
    } finally {
      jest.useRealTimers();
    }
  });

  it('makes the private handoff reachable by keyboard', async () => {
    const user = userEvent.setup();
    render(<SecurityPage />);
    await user.tab();
    expect(screen.getByRole('link', { name: 'Report privately on GitHub' })).toHaveFocus();
  });

  it('gives safe reporting guidance without unsupported assurances or response promises', () => {
    render(<SecurityPage />);
    const main = screen.getByRole('main');
    expect(main).toHaveTextContent('Do not post vulnerability details in a public issue.');
    expect(main).toHaveTextContent('personal data and secrets removed');
    expect(main).toHaveTextContent('Avoid accessing other people');
    expect(main).not.toHaveTextContent(
      /SOC.?2|end.to.end encryption|third.party|AES.256|24.?48|within.*hours/i,
    );
  });
});
