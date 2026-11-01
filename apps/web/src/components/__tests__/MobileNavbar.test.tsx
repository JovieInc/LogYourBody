import { fireEvent, render, screen } from '@testing-library/react';
import { Header } from '../Header';

jest.mock('lucide-react', () => {
  const Icon = (props: React.SVGProps<SVGSVGElement>) => <svg {...props} />;
  return Object.assign(Icon, { __esModule: true, default: Icon, Menu: Icon, X: Icon });
});

it('offers public information and the iPhone app in the marketing navigation', () => {
  render(<Header />);
  expect(screen.getByRole('link', { name: 'iOS' })).toHaveAttribute('href', '/download/ios');
  for (const link of screen.getAllByRole('link')) {
    expect(link.getAttribute('href')).not.toMatch(
      /^\/(dashboard|log|photos|settings|onboarding|steps|import|training)(\/|$)/,
    );
  }
});

it('keeps mobile navigation keyboard accessible after retiring the product navbar', () => {
  render(<Header />);
  const trigger = screen.getByRole('button', { name: 'Open main menu' });
  fireEvent.click(trigger);
  expect(trigger).toHaveAttribute('aria-expanded', 'true');
  expect(screen.getByRole('navigation', { name: 'Mobile' })).toBeInTheDocument();
  fireEvent.keyDown(trigger, { key: 'Escape' });
  expect(trigger).toHaveAttribute('aria-expanded', 'false');
  expect(trigger).toHaveFocus();
  expect(screen.queryByRole('navigation', { name: 'Mobile' })).not.toBeInTheDocument();
});
