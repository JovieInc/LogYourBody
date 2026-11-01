import { createElement } from 'react';
import { render, screen } from '@testing-library/react';
import { Providers } from '../providers';

jest.mock('@/contexts/ProductAuthContext', () => {
  throw new Error('Marketing must not load product auth');
});
jest.mock('@/components/PWAProvider', () => {
  throw new Error('Marketing must not load the PWA app runtime');
});

describe('landing-only providers (LYB-100)', () => {
  it('renders public content without loading account or PWA providers', () => {
    render(createElement(Providers, null, createElement('p', null, 'Public content')));
    expect(screen.getByText('Public content')).toBeVisible();
  });
});
