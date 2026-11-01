/** @jest-environment node */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { GET } from '../route';

jest.mock('next/navigation', () => ({ redirect: jest.fn() }));
import { redirect } from 'next/navigation';

describe('legacy auth URLs (LYB-100)', () => {
  it('redirects sign-in to the landing page without rendering an auth form', () => {
    GET();
    expect(redirect).toHaveBeenCalledWith('/');
    expect(existsSync(join(process.cwd(), 'src/app/signin/page.tsx'))).toBe(false);
  });
});
