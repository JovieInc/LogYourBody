/** @jest-environment node */
import fs, { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
jest.mock('server-only', () => ({}));
import { getAllPosts, getAllSlugs, getPostBySlug, getPostsByTag } from '../blog';

describe('unverified editorial publication boundary', () => {
  it('preserves published YAML metadata, including dates, lists and explicit false', async () => {
    const frontmatter = [
      '---',
      'draft: false',
      'title: "YAML: metadata compatibility"',
      'date: 2026-10-14',
      'author: Parser fixture',
      'tags: [Science, "Progress Tracking"]',
      'excerpt: >-',
      '  First line',
      '  second line',
      '---',
      '',
      'Published body.',
    ].join('\n');
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'readFileSync').mockReturnValue(frontmatter);
    try {
      const post = await getPostBySlug('yaml-metadata-compatibility');
      expect(post).toMatchObject({
        slug: 'yaml-metadata-compatibility',
        title: 'YAML: metadata compatibility',
        date: '2026-10-14',
        author: 'Parser fixture',
        tags: ['Science', 'Progress Tracking'],
        excerpt: 'First line second line',
        content: 'Published body.',
      });
      expect(new Date(post!.date).toISOString()).toBe('2026-10-14T00:00:00.000Z');
    } finally {
      jest.restoreAllMocks();
    }
  });

  it('withholds drafts from lists, tags, static params, direct routes and raw public URLs', async () => {
    const names = readdirSync(path.join(process.cwd(), 'content/blog')).filter((name) =>
      name.endsWith('.md'),
    );
    expect(names).toHaveLength(5);
    expect(await getAllPosts()).toEqual([]);
    expect(await getAllSlugs()).toEqual([]);
    expect(await getPostsByTag('hypertrophy')).toEqual([]);
    for (const name of names) {
      expect(await getPostBySlug(name.slice(0, -3))).toBeNull();
      expect(existsSync(path.join(process.cwd(), 'public/blog', name))).toBe(false);
    }
  });
});
