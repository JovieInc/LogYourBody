import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const workflow = readFileSync(join(root, '.github/workflows/ios-release-loop.yml'), 'utf8');

describe('iOS release publication', () => {
  it('pins the release tag with GITHUB_TOKEN and does not mint a workflow-scoped app token', () => {
    expect(workflow).toContain('pin-ios-release-tag.sh');
    expect(workflow).toContain('create-ios-github-release.sh');
    expect(workflow).toContain('GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}');
    expect(workflow).not.toContain('create-github-app-token');
    expect(workflow).not.toContain('permission-workflows:');
    expect(workflow).not.toContain('JOVIE_BOT_PRIVATE_KEY');
    expect(workflow).not.toContain('gh release create');
  });
});
