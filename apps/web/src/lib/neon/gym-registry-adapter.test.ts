/** @jest-environment node */
import type { NeonQueryFunction } from '@neondatabase/serverless';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createNeonGymRegistry } from './gym-registry-adapter';
import { CATALOG_EQUIPMENT } from '@/lib/training/catalog';

const id = '11111111-1111-4111-8111-111111111111';
const admission = { subject: 'owner-a', ownerId: id };
const gym = { id, name: 'Home', region: null, equipment: [], preferredMachines: [] };
function harness() {
  const query = jest.fn((sql: string, values: unknown[]) => ({ sql, values }));
  const transaction = jest.fn();
  const adapter = createNeonGymRegistry({ query, transaction } as unknown as NeonQueryFunction<
    false,
    false
  >);
  return { query, transaction, adapter };
}
describe('gym persistence boundary and migration drift', () => {
  it('sets transaction-local subject context before the scoped read', async () => {
    const h = harness();
    h.transaction.mockResolvedValue([[], [{ id, payload: gym }]]);
    expect(await h.adapter.list('owner-a')).toEqual([gym]);
    const statements = h.transaction.mock.calls[0][0];
    expect(statements[0]).toMatchObject({
      sql: expect.stringContaining("set_config('app.user_subject', $1, true)"),
      values: ['owner-a'],
    });
    expect(statements[1]).toMatchObject({
      sql: expect.stringContaining('user_subject = $1'),
      values: ['owner-a'],
    });
  });
  it('fences writes with account admission and never revives deleted gyms', async () => {
    const h = harness();
    h.transaction.mockResolvedValue([[], [], [{ id }]]);
    expect(await h.adapter.save(admission, gym)).toBe(true);
    const statements = h.transaction.mock.calls[0][0];
    expect(statements[0]).toMatchObject({
      sql: expect.stringContaining('lyb_native_account_admit'),
      values: ['owner-a', id],
    });
    expect(statements[1].values).toEqual(['owner-a']);
    expect(statements[2].values).toEqual([id, id, 'owner-a', JSON.stringify(gym)]);
    expect(statements[2].sql).toContain('public.gyms.deleted_at is null');
    expect(statements[2].sql).toContain('public.gyms.owner_id = excluded.owner_id');
    h.transaction.mockResolvedValue([[], [], []]);
    expect(await h.adapter.save(admission, gym)).toBe(false);
  });
  it('soft deletes within the admitted owner and propagates failed transactions', async () => {
    const h = harness();
    h.transaction.mockResolvedValue([[], [], []]);
    await h.adapter.remove(admission, id);
    expect(h.transaction.mock.calls[0][0][2]).toMatchObject({
      sql: expect.stringContaining('deleted_at = coalesce(deleted_at, now())'),
      values: [id, 'owner-a', id],
    });
    h.transaction.mockRejectedValue({ code: 'LYB01' });
    await expect(h.adapter.save(admission, gym)).rejects.toMatchObject({ code: 'account_changed' });
  });
  it('retains every V4 entity unchanged and wires the additive V5 registry into both model groups', () => {
    const root = join(process.cwd(), '../ios');
    const models = join(root, 'LogYourBody/Models/LogYourBody.xcdatamodeld');
    const old = readFileSync(join(models, 'LogYourBodyV4.xcdatamodel/contents'), 'utf8');
    const current = readFileSync(join(models, 'LogYourBodyV5.xcdatamodel/contents'), 'utf8');
    const added = current.match(/    <entity name="CachedGymRegistry"[\s\S]*?<\/entity>\n/)?.[0];
    expect(added).toContain('attribute name="ownerId"');
    expect(current.replace(added!, '')).toBe(old);
    expect(readFileSync(join(models, '.xccurrentversion'), 'utf8')).toContain(
      'LogYourBodyV5.xcdatamodel',
    );
    const project = readFileSync(join(root, 'LogYourBody.xcodeproj/project.pbxproj'), 'utf8');
    expect(project.match(/currentVersion = .*LogYourBodyV5/g)).toHaveLength(2);
    const modelGroup = project.match(
      /\/\* Models \*\/ = \{\s*isa = PBXGroup;\s*children = \(([\s\S]*?)\);/,
    )?.[1];
    expect(modelGroup).toContain('/* Gym.swift */');
  });
  it('keeps native inventory IDs aligned with the exercise catalog and migration registered', () => {
    const native = readFileSync(join(process.cwd(), '../ios/LogYourBody/Models/Gym.swift'), 'utf8');
    for (const item of CATALOG_EQUIPMENT) expect(native).toContain(item);
    const migration = readFileSync(
      join(process.cwd(), 'db/migrations/20261025160000_gym_registry.sql'),
      'utf8',
    );
    expect(migration).toContain('enable row level security');
    expect(migration).toContain('force row level security');
    expect(migration).toContain("values ('20261025160000_gym_registry')");
    expect(migration).toContain('on delete cascade');
  });
});
