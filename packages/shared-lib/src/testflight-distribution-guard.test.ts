import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const fastfilePath = `${repoRoot}/apps/ios/fastlane/Fastfile`;
const projectPath = `${repoRoot}/apps/ios/LogYourBody.xcodeproj/project.pbxproj`;
const deployWorkflowPath = `${repoRoot}/.github/workflows/ios-testflight-deploy.yml`;

describe('TestFlight distribution guard', () => {
  it('waits for processing before assigning tester groups', () => {
    const fastfile = readFileSync(fastfilePath, 'utf8');
    const uploadOptions = fastfile.match(
      /testflight_upload_options = lambda do \|ipa:, groups:, distribute_external:, changelog: nil\|([\s\S]*?)\n {2}end/,
    )?.[0];

    expect(uploadOptions).toBeDefined();
    expect(uploadOptions).toContain('skip_waiting_for_build_processing: false');
    expect(uploadOptions).toContain('groups: groups');
    expect(uploadOptions).toContain('distribute_external: distribute_external');

    const deployWorkflow = readFileSync(deployWorkflowPath, 'utf8');
    expect(deployWorkflow).toContain('timeout-minutes: 60');
  });

  it('does not embed Swift source as an app extension', () => {
    const project = readFileSync(projectPath, 'utf8');

    expect(project).not.toContain('Embed Foundation Extensions');
    expect(project).not.toContain('LiquidGlassCTAButton.swift in Embed Foundation Extensions');
  });
});
