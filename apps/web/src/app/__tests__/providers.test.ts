import { createElement } from 'react';
import { render, screen } from '@testing-library/react';
import { usePathname } from 'next/navigation';
import { Providers } from '../providers';

jest.mock('@/contexts/ProductAuthContext', () => ({
  ProductAuthProvider: () => {
    throw new Error('Web must not mount product authentication');
  },
}));
jest.mock('@/components/PWAProvider', () => ({
  PWAProvider: () => {
    throw new Error('Web must not mount the installed product app');
  },
}));

it.each([
  '/',
  '/landing',
  '/privacy',
  '/security',
  '/terms',
  '/unknown',
  '/dashboard',
  '/settings/profile',
])('renders %s without product authentication or PWA registration', (pathname) => {
  jest.mocked(usePathname).mockReturnValue(pathname);
  render(createElement(Providers, null, createElement('main', null, 'Public website')));
  expect(screen.getByRole('main')).toHaveTextContent('Public website');
});
