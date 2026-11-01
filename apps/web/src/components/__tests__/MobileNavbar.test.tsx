/** @jest-environment node */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('retired app navigation (LYB-100)', () => {
  it('removes the dashboard, log and settings navbar', () => {
    expect(existsSync(join(process.cwd(), 'src/components/MobileNavbar.tsx'))).toBe(false);
  });

  it('removes app navigation shortcuts from the public web manifest', () => {
    const manifest = JSON.parse(
      readFileSync(join(process.cwd(), 'public/site.webmanifest'), 'utf8'),
    );
    expect(manifest.start_url).toBe('/');
    expect(manifest).not.toHaveProperty('shortcuts');
  });

  it('keeps retained UI links and navigation free of retired app destinations', () => {
    function uiFiles(directory: string): string[] {
      return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const file = join(directory, entry.name);
        if (['api', '__tests__', 'generated'].includes(entry.name)) return [];
        if (entry.isDirectory()) return uiFiles(file);
        return /\.[jt]sx?$/.test(entry.name) && !/\.(test|spec)\./.test(entry.name) ? [file] : [];
      });
    }
    const retired = '(?:dashboard|log|photos|settings|onboarding|steps|import|training)';
    const destination = new RegExp(
      `(?:href\\s*(?:=\\s*\\{?|:)|(?:push|replace|redirect|assign)\\s*\\()\\s*['"\x60]/${retired}(?:[/#?'"\x60]|$)`,
    );
    for (const file of uiFiles(join(process.cwd(), 'src'))) {
      expect({ file, deadLink: destination.test(readFileSync(file, 'utf8')) }).toEqual({
        file,
        deadLink: false,
      });
    }
  });

  it('does not mount auth or PWA app chrome around public pages or 404s', () => {
    for (const file of ['layout.tsx', 'providers.tsx']) {
      const source = readFileSync(join(process.cwd(), 'src/app', file), 'utf8');
      expect(source).not.toMatch(
        /ProductAuthProvider|AuthRuntimeProvider|PWAProvider|PWAInstallPrompt|ServiceWorkerUpdater/,
      );
    }
  });
});
