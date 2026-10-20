import React from 'react';
import { render, screen } from '@testing-library/react';

jest.mock('lucide-react', () => {
  const Icon = (props: React.SVGProps<SVGSVGElement>) => <svg data-icon="mock-icon" {...props} />;

  return Object.assign(Icon, {
    __esModule: true,
    default: Icon,
    Download: Icon,
    ExternalLink: Icon,
    FileText: Icon,
    Mail: Icon,
    MessageCircle: Icon,
    ShieldCheck: Icon,
    Smartphone: Icon,
  });
});

jest.mock('@/components/Header', () => ({
  Header: () => <header data-testid="site-header" />,
}));

jest.mock('@/components/Footer', () => ({
  Footer: () => <footer data-testid="site-footer" />,
}));

jest.mock('@/components/MarkdownRenderer', () => ({
  MarkdownRenderer: ({ content }: { content: string }) => (
    <article data-testid="legal-document">{content}</article>
  ),
}));

jest.mock('@/lib/load-legal-docs', () => ({
  loadLegalDocument: jest.fn(async (documentName: string) => `Loaded ${documentName} legal copy`),
}));

jest.mock('next/link', () => {
  const Link = ({
    children,
    href,
    ...props
  }: React.PropsWithChildren<{ href: string } & React.AnchorHTMLAttributes<HTMLAnchorElement>>) => (
    <a href={href} {...props}>
      {children}
    </a>
  );

  return Object.assign(Link, { __esModule: true, default: Link });
});

describe('production-adjacent readiness pages', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('keeps the delete-account web page positioned as iOS deletion plus support fallback', async () => {
    const { default: DeleteAccountPage } = await import('../delete-account/page');

    render(<DeleteAccountPage />);

    expect(
      screen.getByRole('heading', { name: /delete your logyourbody account/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/you can permanently delete your account from the ios app/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/support can help process the request by email/i)).toBeInTheDocument();

    expect(screen.getByRole('link', { name: /download ios app/i })).toHaveAttribute(
      'href',
      '/download/ios',
    );

    const emailSupportLink = screen.getByRole('link', { name: /email support/i });
    expect(emailSupportLink).toHaveAttribute(
      'href',
      expect.stringContaining('mailto:support@logyourbody.com'),
    );
    expect(emailSupportLink).toHaveAttribute(
      'href',
      expect.stringContaining('LogYourBody%20Account%20Deletion%20Request'),
    );
    expect(emailSupportLink).toHaveAttribute(
      'href',
      expect.stringContaining('permanently%20delete%20my%20LogYourBody%20account'),
    );

    expect(screen.queryByRole('button', { name: /delete account/i })).not.toBeInTheDocument();
    expect(document.querySelector('form')).not.toBeInTheDocument();
  });

  it('exposes support, data-export, legal, download, and deletion help links', async () => {
    const { default: SupportPage } = await import('../support/page');

    render(<SupportPage />);

    expect(screen.getByRole('heading', { name: /how can we help/i })).toBeInTheDocument();
    expect(
      screen
        .getAllByRole('link', { name: /support@logyourbody\.com/i })
        .some((link) => link.getAttribute('href') === 'mailto:support@logyourbody.com'),
    ).toBe(true);
    expect(screen.getByRole('link', { name: /request a data export by email/i })).toHaveAttribute(
      'href',
      expect.stringContaining('LogYourBody%20Data%20Export%20Request'),
    );

    expect(
      screen
        .getAllByRole('link', { name: /privacy policy/i })
        .some((link) => link.getAttribute('href') === '/privacy'),
    ).toBe(true);
    expect(screen.getByRole('link', { name: /terms of service/i })).toHaveAttribute(
      'href',
      '/terms',
    );
    expect(screen.getByRole('link', { name: /download apps/i })).toHaveAttribute(
      'href',
      '/download',
    );
    expect(screen.getByRole('link', { name: /delete account/i })).toHaveAttribute(
      'href',
      '/delete-account',
    );
  });

  it('loads the shared privacy policy legal document', async () => {
    const { loadLegalDocument } = await import('@/lib/load-legal-docs');
    const { default: PrivacyPage } = await import('../privacy/page');

    render(await PrivacyPage());

    expect(loadLegalDocument).toHaveBeenCalledWith('privacy');
    expect(screen.getByTestId('legal-document')).toHaveTextContent('Loaded privacy legal copy');
  });

  it('loads the shared terms legal document', async () => {
    const { loadLegalDocument } = await import('@/lib/load-legal-docs');
    const { default: TermsPage } = await import('../terms/page');

    render(await TermsPage());

    expect(loadLegalDocument).toHaveBeenCalledWith('terms');
    expect(screen.getByTestId('legal-document')).toHaveTextContent('Loaded terms legal copy');
  });
});
