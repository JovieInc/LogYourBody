import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const requiredFragments = {
  ci: [
    // Every active branch ruleset requires the aggregate "CI Summary" check, so
    // CI must emit it for pull requests and merge groups on both protected
    // branches — main and production — or those rulesets deadlock.
    /\n\s*pull_request:\s*\n\s*branches:\s*\[main,\s*production\]/,
    /\n\s*merge_group:\s*\n\s*branches:\s*\[main,\s*production\]/,
    /types:\s*\[checks_requested\]/,
    /cancel-in-progress:\s*\$\{\{ github\.event_name != 'merge_group'/,
    /github\.event_name == 'merge_group'/,
    /github\.event\.merge_group\.base_sha/,
    /github\.event\.merge_group\.head_sha/,
    /assert_expected_result/,
    /needs\.detect-changes\.result[^\n]+success/,
  ],
  tokenEnrollment: [
    /workflow_run:/,
    /workflows:\s*\[Native Merge Queue Enrollment\]/,
    /secrets\.MERGE_QUEUE_TOKEN/,
    /CI Summary/,
    /dequeuePullRequest/,
    /enqueuePullRequest/,
    /expectedHeadOid:\s*pull\.headRefOid/,
    /nameWithOwner !== `\$\{owner\}\/\$\{repo\}`/,
  ],
  enrollment: [
    /workflow_run:/,
    /workflows:\s*\[CI\]/,
    /pull-requests:\s*write/,
    /run\.conclusion !== 'success'/,
    /recordOutcome/,
    /pull\.head\.sha !== run\.head_sha/,
    /pull\.draft/,
    /enqueuePullRequest/,
    /expectedHeadOid:\s*pull\.head\.sha/,
  ],
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const guardPaths = ['canon', 'guards', '.github/workflows/company-guards.yml'];
const fullSHA = /^[a-f0-9]{40}$/;

function guardTree(tree) {
  assert(tree.truncated === false && Array.isArray(tree.tree), 'Company guard tree is incomplete');
  for (const name of guardPaths) {
    assert(tree.tree.some(({ path }) => path === name), `Company guard tree is missing ${name}`);
  }
  const entries = tree.tree
    .filter(({ path }) => guardPaths.some((name) => path === name || path.startsWith(`${name}/`)))
    .map(({ path, mode, type, sha }) => [path, mode, type, sha])
    .sort((a, b) => a[0].localeCompare(b[0]));
  assert(entries.every(([, mode, type, sha]) =>
    typeof mode === 'string' && /^(?:100644|100755|120000|040000)$/.test(mode) &&
    ['blob', 'tree'].includes(type) && fullSHA.test(sha)), 'Company guard tree metadata is incomplete');
  return entries;
}

// The shared drift check only recognizes commits touching guardPaths. A newer
// certification-only commit can be falsely stale even when it is main's tip.
export function refreshCompanyPins(rootDirectory, api) {
  const head = api('commits/main').sha;
  assert(fullSHA.test(head), 'Company main must resolve to a full commit SHA');
  const candidates = guardPaths.flatMap((name) => {
    const commits = api(`commits?sha=${head}&path=${encodeURIComponent(name)}&per_page=1`);
    assert(Array.isArray(commits) && commits.length === 1, `No company guard history for ${name}`);
    const [commit] = commits;
    assert(fullSHA.test(commit.sha) && Number.isFinite(Date.parse(commit.commit?.committer?.date)),
      `Invalid company guard history for ${name}`);
    return commits;
  }).sort((a, b) => Date.parse(b.commit.committer.date) - Date.parse(a.commit.committer.date));
  const guard = candidates[0].sha;
  assert(
    JSON.stringify(guardTree(api(`git/trees/${guard}?recursive=1`))) ===
      JSON.stringify(guardTree(api(`git/trees/${head}?recursive=1`))),
    'Company guard pin would omit changes from main',
  );
  const updates = [
    ['company-guards', guard],
    ['public-app-certification', head],
  ].map(([name, sha]) => {
    const file = path.join(rootDirectory, `.github/workflows/${name}.yml`);
    assert(fs.lstatSync(file).isFile(), `Company pin input must be a regular file: ${name}`);
    const source = fs.readFileSync(file, 'utf8');
    const uses = new RegExp(`^    uses: JovieInc/ci/\\.github/workflows/${name}\\.yml@([a-f0-9]{40})$`, 'gm');
    const input = /^      ci-ref: ([a-f0-9]{40})$/gm;
    const pins = [...source.matchAll(uses)];
    const refs = [...source.matchAll(input)];
    assert(pins.length === 1 && refs.length === 1 && pins[0][1] === refs[0][1],
      `Company workflow pins must be unique full SHAs and agree: ${name}`);
    return [file, source.replace(uses, `    uses: JovieInc/ci/.github/workflows/${name}.yml@${sha}`)
      .replace(input, `      ci-ref: ${sha}`)];
  });
  // Validate both workflows and upstream trees before changing either caller.
  for (const [file, source] of updates) fs.writeFileSync(file, source);
  return { guards: guard, certification: head };
}

export function verifyCompanyGuards(ciWorkflow, companyGuardsWorkflow) {
  const job = (workflow, name) =>
    workflow.match(new RegExp(`\\n  ${name}:\\n[\\s\\S]*?(?=\\n  [\\w-]+:|$)`))?.[0] ?? '';
  const caller = job(ciWorkflow, 'company-guards');
  const detection = job(ciWorkflow, 'detect-changes').split('\n    steps:')[0];
  const summary = job(ciWorkflow, 'ci-summary');
  const summaryFailure = summary.slice(summary.indexOf('\n          if [[ "${{ needs.detect-changes.result }}"'));
  const shared = job(companyGuardsWorkflow, 'company-guards');
  const sharedPin = shared.match(/uses: JovieInc\/ci\/\.github\/workflows\/company-guards.yml@([a-f0-9]{40})\n/)?.[1];
  assert(
    caller.includes('    uses: ./.github/workflows/company-guards.yml\n'),
    'Company Guards must run the canonical reusable workflow',
  );
  assert(
    /\n    needs: company-guards\n/.test(detection),
    'Company Guards must gate Detect Changes',
  );
  for (const block of [caller, detection, shared]) {
    assert(
      !/\n    (?:if|continue-on-error):/.test(block),
      'Company Guards and detection must not be conditional or advisory',
    );
  }
  assert(
    /\n  workflow_call:\s*\n/.test(companyGuardsWorkflow) &&
      sharedPin && shared.includes(`      ci-ref: ${sharedPin}\n`),
    'Company Guards must expose the pinned company workflow through workflow_call',
  );
  assert(
    /\n    if: always\(\)\n/.test(summary) &&
      /\n    needs: \[detect-changes,/.test(summary) &&
      !/\n(?: {4}continue-on-error:| {8}(?:if|continue-on-error):)/.test(summary) &&
      /\n            exit 1\n          fi\n/.test(summaryFailure) &&
      summary.includes('needs.detect-changes.result }}" != "success"'),
    'Company Guards failures must reach the required CI Summary',
  );
  return true;
}

export function verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow, tokenEnrollmentWorkflow }) {
  assert(policy.schema_version === 1, 'policy schema_version must be 1');
  assert(policy.repository === 'JovieInc/LogYourBody', 'policy must remain repository-local');
  assert(
    policy.target_ref === 'refs/heads/main',
    'target_ref must be refs/heads/main with no embedded quotes',
  );
  assert(policy.required_status_check === 'CI Summary', 'required status must be CI Summary');
  assert(policy.merge_queue?.required === true, 'native merge queue must be required');
  assert(policy.merge_queue?.merge_method === 'MERGE', 'queue merge method must be MERGE');
  // PRs land on normal checks alone; certification happens post-merge (canary/dogfood), never as a PR gate.
  assert(
    policy.auto_enrollment?.certification_label === undefined,
    'auto-enrollment must not require a certification label',
  );
  assert(policy.auto_enrollment?.exact_head_required === true, 'exact-head proof is required');
  assert(policy.auto_enrollment?.same_repository_only === true, 'fork auto-enrollment is forbidden');

  for (const fragment of requiredFragments.ci) {
    assert(fragment.test(ciWorkflow), `CI workflow is missing required contract: ${fragment}`);
  }
  for (const fragment of requiredFragments.enrollment) {
    assert(
      fragment.test(enrollmentWorkflow),
      `auto-enrollment workflow is missing required contract: ${fragment}`,
    );
  }

  // Only this negative hold predicate may inspect labels. Positive certification
  // gates remain forbidden, and missing label evidence must block admission.
  const holdPredicate = "const hasExplicitHold = !Array.isArray(pull.labels) || pull.labels.some(label => typeof label?.name !== 'string' || label.name.toLowerCase() === 'hold');";
  const normalizedEnrollment = enrollmentWorkflow.replace(/\s+/g, ' ');
  assert(normalizedEnrollment.includes(holdPredicate), 'auto-enrollment must preserve explicit holds');
  const withoutHoldPredicate = normalizedEnrollment.replace(holdPredicate, '');
  assert(!/labels\.some|\.labels\b/.test(withoutHoldPredicate), 'auto-enrollment must not gate on PR labels except the negative hold predicate');
  assert(/if \(hasExplicitHold\) \{ await recordOutcome\('NOT_ELIGIBLE', '[^']+'\); return; \}/.test(normalizedEnrollment), 'an explicit hold must return before admission');

  assert(!/actions\/checkout@/.test(enrollmentWorkflow), 'privileged enrollment must not checkout code');
  assert(!/secrets\./.test(enrollmentWorkflow), 'auto-enrollment must not receive repository secrets');

  if (policy.token_enrollment) {
    assert(
      policy.token_enrollment.secret === 'MERGE_QUEUE_TOKEN',
      'token enrollment must use the MERGE_QUEUE_TOKEN secret',
    );
    assert(typeof tokenEnrollmentWorkflow === 'string', 'token enrollment workflow must exist');
    for (const fragment of requiredFragments.tokenEnrollment) {
      assert(fragment.test(tokenEnrollmentWorkflow), `token enrollment is missing required contract: ${fragment}`);
    }
    assert(!/actions\/checkout@/.test(tokenEnrollmentWorkflow), 'token enrollment must not checkout code');
    assert(!/pull_request/.test(tokenEnrollmentWorkflow), 'token enrollment must not run on pull request events');
  }
  return true;
}

export function verifyRepository(rootDirectory) {
  const policyPath = path.join(rootDirectory, '.github/merge-queue-policy.json');
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
  const ciWorkflow = fs.readFileSync(path.join(rootDirectory, '.github/workflows/ci.yml'), 'utf8');
  verifyCompanyGuards(
    ciWorkflow,
    fs.readFileSync(path.join(rootDirectory, '.github/workflows/company-guards.yml'), 'utf8'),
  );
  const enrollmentWorkflow = fs.readFileSync(
    path.join(rootDirectory, policy.auto_enrollment.workflow),
    'utf8',
  );
  const tokenEnrollmentWorkflow = policy.token_enrollment
    ? fs.readFileSync(path.join(rootDirectory, policy.token_enrollment.workflow), 'utf8')
    : undefined;
  return verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow, tokenEnrollmentWorkflow });
}

const isMainModule = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMainModule) {
  if (process.argv[2] === '--refresh-company-pins') {
    const pins = refreshCompanyPins(process.cwd(), (endpoint) => JSON.parse(execFileSync(
      'gh', ['api', '--hostname', 'github.com', `repos/JovieInc/ci/${endpoint}`], { encoding: 'utf8' },
    )));
    console.log(`Company pins refreshed: guards=${pins.guards} certification=${pins.certification}`);
  } else {
    assert(process.argv.length === 2, 'Unknown policy verifier argument');
  }
  verifyRepository(process.cwd());
  console.log('Repository-native merge queue policy verified.');
}
