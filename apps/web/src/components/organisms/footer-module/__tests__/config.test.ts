import { resolveFooterVariant } from '../config';

describe('resolveFooterVariant', () => {
  it('keeps explicit full and compact modes', () => {
    expect(resolveFooterVariant('full', '/privacy')).toBe('full');
    expect(resolveFooterVariant('compact', '/about')).toBe('compact');
  });

  it('uses compact on locked legal and security routes', () => {
    expect(resolveFooterVariant('auto', '/privacy')).toBe('compact');
    expect(resolveFooterVariant('auto', '/terms/')).toBe('compact');
    expect(resolveFooterVariant('auto', '/health-disclosure')).toBe('compact');
    expect(resolveFooterVariant('auto', '/security')).toBe('compact');
  });

  it('uses full on marketing, support, download, and blog routes', () => {
    expect(resolveFooterVariant('auto', '/')).toBe('full');
    expect(resolveFooterVariant('auto', '/about')).toBe('full');
    expect(resolveFooterVariant('auto', '/support')).toBe('full');
    expect(resolveFooterVariant('auto', '/download')).toBe('full');
    expect(resolveFooterVariant('auto', '/blog')).toBe('full');
    expect(resolveFooterVariant('auto', null)).toBe('full');
  });
});
