import { prefersMarkdown, varyOnAccept } from '../accept-markdown';

describe('public HTTP representation preference (RFC9110)', () => {
  it.each([
    [null, false],
    ['', false],
    ['*/*', false],
    ['text/*', false],
    ['text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', false],
    ['text/markdown', true],
    ['TEXT/MARKDOWN;Q=1', true],
    ['text/markdown;q=0.9,text/html;q=0.5', true],
    ['text/html;q=0.9,text/markdown;q=0.5', false],
    ['text/markdown,text/html', false],
    ['text/html,text/markdown', false],
    ['text/markdown;q=0,*/*;q=1', false],
    ['text/html;q=0,text/*;q=0.8', true],
    ['text/markdown;q=0.1,text/*;q=0.9', false],
    ['text/markdown;q=0.9,text/html;q=0.1,*/*;q=1', true],
    ['text/markdown;q=0.1234,text/html;q=0.1', false],
    ['text/markdown;q=2,text/html;q=0.1', false],
    ['text/markdown;q=bogus,text/html;q=0.1', false],
    ['text/markdown;q=0.5;q=1,text/html;q=0.1', false],
    ['text/markdown;q=0,text/markdown;q=1', false],
    ['text/markdown;charset="UTF-8"', true],
    ['text/markdown;charset=iso-8859-1,text/html', false],
    ['text/markdown;profile="a,b",text/html', false],
    ['text/markdown;profile="a;b",text/html', false],
    ['application/json', false],
    ['text/markdown;profile="unfinished', false],
  ])('%s selects Markdown=%s', (accept, expected) => {
    expect(prefersMarkdown(accept)).toBe(expected);
  });

  it('merges Vary without losing framework variants or duplicating Accept', () => {
    const headers = new Headers({ Vary: 'RSC, Next-Router-State-Tree' });
    varyOnAccept(headers);
    expect(headers.get('Vary')).toBe('RSC, Next-Router-State-Tree, Accept');
    varyOnAccept(headers);
    expect(headers.get('Vary')).toBe('RSC, Next-Router-State-Tree, Accept');
    headers.set('Vary', '*');
    varyOnAccept(headers);
    expect(headers.get('Vary')).toBe('*');
  });

  it('cannot use repeated charset parameters to outrank an explicit q=0', () => {
    const duplicateParameters = ';charset=utf-8'.repeat(201);
    expect(prefersMarkdown('text/markdown;q=0,text/*' + duplicateParameters)).toBe(false);
  });
});
