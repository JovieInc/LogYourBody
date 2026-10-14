import { render, screen } from '@testing-library/react';
import NotFound from '../not-found';
jest.mock('@/components/Header', () => ({ Header: () => <header /> }));
jest.mock('@/components/Footer', () => ({ Footer: () => <footer /> }));
describe('marketing recovery without a product-auth provider', () => {
  it('renders a semantic 404 and real home/support links with no nested controls', () => {
    const { container } = render(<NotFound />);
    expect(screen.getByRole('heading', { level: 1, name: 'Page not found' })).toBeInTheDocument();
    expect(screen.getByRole('main')).toHaveAttribute('id', 'main-content');
    expect(screen.getByRole('link', { name: 'Go home' })).toHaveAttribute('href', '/');
    expect(screen.getByRole('link', { name: 'Contact support' })).toHaveAttribute(
      'href',
      '/support',
    );
    expect(container.querySelector('a button, button a')).toBeNull();
  });
});
