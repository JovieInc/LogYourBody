import { expect, it } from 'vitest';
import { savedCacheRowsMissingLastModified } from './saved-cache-row-last-modified';

it('accepts a copied, deleted, or keyed cache row and still rejects a bare save', () => {
  const copied =
    'func copy() {\n let row = CachedBodyMetrics(context: context)\n row.setValuesForKeys(source.dictionaryWithValues(forKeys: Array(source.entity.attributesByName.keys)))\n try context.save()\n}';
  const deleted =
    'func drop() {\n let row = CachedDailyMetrics(context: context)\n context.delete(row)\n try context.save()\n}';
  const keyed =
    'func keyed() {\n let row = CachedBodyMetrics(context: context)\n row.setValue(date, forKey: "lastModified")\n try context.save()\n}';
  const bare =
    'func seed() {\n let row = CachedBodyMetrics(context: context)\n try context.save()\n}';
  expect(savedCacheRowsMissingLastModified(copied)).toEqual([]);
  expect(savedCacheRowsMissingLastModified(deleted)).toEqual([]);
  expect(savedCacheRowsMissingLastModified(keyed)).toEqual([]);
  expect(savedCacheRowsMissingLastModified(bare)).toEqual([
    'seed: row is saved without lastModified',
  ]);
});
