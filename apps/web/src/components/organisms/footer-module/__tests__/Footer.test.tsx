import { render, screen } from '@testing-library/react';
import { Footer } from '../Footer';
import { FOOTER_PEN_CONTRACT_ID, FOOTER_STATE_GALLERY_ID } from '../config';
import { APP_CONFIG } from '@/constants/app';
import { logYourBody } from '@jovieinc/product-registry';

const mockUsePathname = jest.fn<() => string | null>(() => '/about');

jest.mock('next/navigation', () => ({
  usePathname: () => mockUsePathname(),
}));

describe('Footer', () => {
  beforeEach(() => {
    mockUsePathname.mockReturnValue('/about');
  });

  it('renders the locked full Footer without a slogan', () => {
    render(<Footer />);

    const footer = screen.getByTestId('marketing-footer');
    expect(footer).toHaveAttribute('data-pen-contract', FOOTER_PEN_CONTRACT_ID);
    expect(footer).toHaveAttribute('data-pen-gallery', FOOTER_STATE_GALLERY_ID);
    expect(footer).toHaveAttribute('data-footer-mode', 'full');

    expect(screen.getByRole('heading', { name: 'Product' })).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Company' })).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Resources' })).toBeVisible();
    expect(screen.getByRole('link', { name: 'Download' })).toHaveAttribute('href', '/download');
    expect(screen.getByRole('link', { name: 'Support' })).toHaveAttribute('href', '/support');
    expect(screen.getByRole('link', { name: 'Status' })).toHaveAttribute(
      'href',
      logYourBody.links.status,
    );

    expect(screen.getByText(`© ${new Date().getFullYear()} ${APP_CONFIG.companyName}`)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Privacy' })).toHaveAttribute('href', '/privacy');
    expect(screen.getByRole('link', { name: 'Terms' })).toHaveAttribute('href', '/terms');
    expect(screen.getByRole('link', { name: 'Health disclosure' })).toHaveAttribute(
      'href',
      '/health-disclosure',
    );

    expect(screen.queryByText(logYourBody.brand.slogan)).not.toBeInTheDocument();
  });

  it('renders compact mode with the logo in the legal row', () => {
    mockUsePathname.mockReturnValue('/privacy');

    render(<Footer />);

    const footer = screen.getByTestId('marketing-footer');
    expect(footer).toHaveAttribute('data-footer-mode', 'compact');
    expect(screen.queryByRole('heading', { name: 'Product' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: `${APP_CONFIG.appName} home` })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Privacy' })).toHaveAttribute('href', '/privacy');
    expect(screen.getByText(`© ${new Date().getFullYear()} ${APP_CONFIG.companyName}`)).toBeInTheDocument();
  });

  it('honors an explicit compact variant on a marketing path', () => {
    render(<Footer variant="compact" />);

    expect(screen.getByTestId('marketing-footer')).toHaveAttribute('data-footer-mode', 'compact');
    expect(screen.queryByRole('heading', { name: 'Company' })).not.toBeInTheDocument();
  });
});
