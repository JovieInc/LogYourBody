# Preview evidence and native queue migration candidate

Status: preparation only. No ruleset, credential, deployment, or queue mutation is
part of this source change. Do not require this check until qualification and the
policy migration are explicitly approved.

## Existing mechanism and chosen extension

GitHub's existing native merge queue and Actions remain the landing substrate.
Vercel's existing project and supported REST API remain the deployment substrate.
The existing LYB production workflow already uses `VERCEL_TOKEN`; this candidate
adds no token, service, controller, package dependency, or provider account.

The GitHub deployment object alone is insufficient: the observed Vercel deployment
has an empty payload and no project ID. Checking only environment `Preview` and a
status context could accept a different project's build. The verifier therefore
uses authenticated Vercel detail reads to bind repository, project, commit, ref,
Preview environment, terminal state and timestamps. It does not use arbitrary
metadata strings as source-SHA proof. Listing filters narrow candidates; detail
readback is authoritative. A newer failed candidate is not replaced by an older
successful candidate. Exact immutable SHA and current provider state determine
validity; there is no arbitrary age-based expiry of a successful immutable build.

Alternatives: keep the existing `required_deployments` rule (GitHub rejected native
queue admission even with successful exact-head Preview); require only the Vercel
status context (does not itself establish project/group-SHA evidence); replace
native queue (contrary to approved landing authority). Extend the existing stack
with the small verifier, not a new delivery platform. Revisit when GitHub supports
this rule combination or Vercel offers equivalent project-bound merge-group proof.

Primary references:
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
- https://vercel.com/docs/rest-api/deployments/create-a-new-deployment
- https://vercel.com/docs/git/vercel-for-github

## Verification

`Preview Evidence` runs on `pull_request` and `merge_group`. It uses PR head SHA
(not the test merge SHA) and the combined group's `head_sha`, respectively. Forks,
wrong repository/base, missing secrets, absent evidence, unsuccessful deployments,
and wrong project/ref/SHA all fail closed. It never creates a deployment.
Tests and coverage must succeed even when the dependency job fails or is skipped;
otherwise the required evidence job explicitly fails. Both jobs have finite caps.

The exact offline command used by the workflow is:

```sh
node --test --experimental-test-coverage --test-reporter=./.github/scripts/preview-coverage-reporter.mjs .github/scripts/preview-evidence.test.mjs
```

It enforces 95% lines, 90% branches and 100% functions for the checker module.
Tests use fake HTTP transport with real file/ledger operations. This establishes
behavior under tested inputs, not provider deployment or real queue qualification.

The workflow reads the existing Vercel credential only in the verification step;
there are no package installs or product-code execution in that job. Like existing
in-repository Actions, the candidate workflow/code must receive independent review
before being trusted as a gate. Forks receive no credential and fail verification.

## One-use operator deployment path

After explicit scope approval and a fresh allocation, the existing landing owner
can run the same helper for a real saved PR or merge-group event payload:

```sh
node .github/scripts/preview-evidence.mjs deploy EVENT_NAME event.json approved-grant.json DURABLE_LEDGER_DIRECTORY
```

The grant file must contain `schema:1`, unique `id`, `repository`, `project`, full
`sha`, `ref`, `event` (`pull_request` or `merge_group`), `environment:"Preview"`,
`attempts:1`, finite `maxMs` <=1200000 and `expiresAt` (Unix milliseconds).
The file is the operator's transcription of the resource lead's explicit grant,
not a self-issued authorization. Retain its origin receipt alongside it. Always
use the same canonical durable ledger directory across invocations; deleting or
changing the ledger to replay a grant is prohibited. A ledger is not a signature
or permission system against a malicious operator.

The helper exclusively claims the grant before POST; ambiguous responses consume
it. It creates one canonical-project Preview from immutable Git source SHA and
ref, records the returned ID, then waits within the grant's remaining budget.
Failure/deadline requests cancellation of only that returned deployment. A failed
cancellation remains an operator cleanup/escalation obligation; an API timeout
with no deployment ID requires read-only provider reconciliation, never a retry.
No production target, alias mutation, rule mutation or queue action exists here.
The workflow can observe this Preview while it waits. No workflow event allocates
a deployment automatically. Routine queue automation would need separate explicit
resource policy; this candidate deliberately cannot invent such authority.

## Qualification and policy sequencing

1. Review and test this source. Preserve all current protections.
2. Obtain approval/allocation for a real PR Preview canary; retain exact SHA,
   project, deployment ID, state/timing and required-check receipt.
3. Prepare current before/proposed/rollback exports. Proposed change adds the
   GitHub Actions `Preview Evidence` required check and removes only incompatible
   `required_deployments: Preview`; CI Summary, native queue and other rules stay.
4. Under explicit policy approval, require and read back the new check before
   removing the incompatible rule. No period without Preview enforcement.
5. Enqueue a reviewed candidate normally; obtain a real `merge_group` event. Only
   then can an explicitly allocated group-SHA Preview prove the provider path.
   The required checker must block the group until that evidence exists. If any
   step fails, restore the exported old policy and hold admission, never bypass.
6. Independently verify queue membership and merged SHA, then deployment/runtime.

A real queue canary *before* changing the incompatible rule is impossible under
its observed rejection. Synthetic payload tests are not a substitute. Thus the
final approval packet must explicitly separate pre-change tests/PR canary from
post-change guarded group canary, with rollback and an unproven group path named.
The first queue canary must include the reviewed checker workflow in its merge
commit; do not assume it exists on current main. Source on #1100 also enables
workspace-based Git Previews; keep its separate review and deployment receipts.

#1103 remains with its docs owner for the new policy-pin head, review and fresh
checks. Rebase after #1100 only if required for gate availability/conflicts, then
regenerate affected source maps and revalidate the resulting exact head.
