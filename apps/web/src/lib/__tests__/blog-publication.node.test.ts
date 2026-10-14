/** @jest-environment node */
import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
jest.mock('server-only', () => ({}));
import { getAllPosts, getAllSlugs, getPostBySlug, getPostsByTag } from '../blog';

describe('unverified editorial publication boundary', () => {
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
