# Draft TestFlight notes locally

This command prepares text for private review. It does not publish a changelog,
contact Apple, or change a workflow.

From a checkout with full release history, run:

    node scripts/ios/draft-testflight-notes.mjs < approved-metadata.json

Supply JSON with:

- **lastDistributed**: the full source commit SHA tied to a successful receipt
  for the last build distributed to the intended TestFlight group. An upload,
  pending processing, and a recent merge are not distribution receipts.
- **candidate**: the full source commit SHA for the proposed next build.
- **entries**: human-reviewed public changelog metadata. Each note has **sha**
  (the merge or squash commit on the release branch), **audience** of "customer",
  **approval** of "approved", **category** of "feature", "fix", or "improvement",
  and single-line customer copy in **note**.

The draft uses the first-parent range (lastDistributed, candidate] and never
reads commit messages, PR or issue titles, or dependency and security notes.
An empty approved range exits 3 without output. Missing history, invalid
provenance, or invalid copy exits 2 without output. Drafts over the local
1,000-character review budget are rejected instead of truncated. The command cannot
authenticate the supplied distribution receipt or a review; the caller must
verify both from trusted records before running it.

A later integration can preserve the existing Fastlane changelog file handoff
after validating exact build and tester-group receipts and collecting approval
for the rendered draft. App Store What's New remains a separate per-version
review; do not feed this draft into App Store metadata or submission.
