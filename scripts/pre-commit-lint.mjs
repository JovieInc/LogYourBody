import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

function git(cwd, args) {
  return spawnSync('git', args, { cwd, encoding: 'utf8' });
}

export function lintArguments(cwd = process.cwd()) {
  const args = ['exec', 'lint-staged'];
  const merge = git(cwd, ['rev-parse', '-q', '--verify', 'MERGE_HEAD']);
  if (merge.status !== 0) return args;
  const incoming = merge.stdout.trim();
  if (!/^[a-f0-9]{40,64}$/.test(incoming)) return args;
  // Only a fetched main ancestor can supply already-integrated source.
  const verified = git(cwd, ['merge-base', '--is-ancestor', incoming, 'refs/remotes/origin/main']);
  if (verified.status !== 0) return args;
  const index = git(cwd, ['write-tree']);
  if (index.status !== 0) throw new Error(index.stderr || 'Cannot snapshot unresolved index');
  const tree = index.stdout.trim();
  if (!/^[a-f0-9]{40,64}$/.test(tree)) throw new Error('Invalid index tree');
  // Include every branch change and conflict resolution, including Swift edits.
  // Use the index tree so unrelated unstaged edits never select extra files.
  return [...args, '--diff', `${incoming} ${tree}`, '--stash', '--hide-partially-staged'];
}

export function runLint(cwd = process.cwd()) {
  const result = spawnSync('pnpm', lintArguments(cwd), { cwd, stdio: 'inherit' });
  if (result.error) throw result.error;
  return result.status ?? 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = runLint();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
