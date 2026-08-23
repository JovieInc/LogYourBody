import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const fastfilePath = `${repoRoot}/apps/ios/fastlane/Fastfile`;
const releaseFastfilePath = `${repoRoot}/apps/ios/fastlane/Fastfile.release`;
const projectPath = `${repoRoot}/apps/ios/LogYourBody.xcodeproj/project.pbxproj`;
const deployWorkflowPath = `${repoRoot}/.github/workflows/ios-testflight-deploy.yml`;

describe('TestFlight distribution guard', () => {
  it('waits for processing before assigning tester groups', () => {
    const fastfile = readFileSync(fastfilePath, 'utf8');
    const uploadOptions = fastfile.match(
      /testflight_upload_options = lambda do \|[\s\S]*?skip_waiting_for_build_processing: false[\s\S]*?\n {2}end/,
    )?.[0];

    expect(uploadOptions).toBeDefined();
    expect(uploadOptions).toContain('groups: groups');
    expect(uploadOptions).toContain('distribute_external: distribute_external');
    expect(uploadOptions).toContain('skip_waiting_for_build_processing: skip_waiting_for_build_processing');

    const releaseFastfile = readFileSync(releaseFastfilePath, 'utf8');
    const distributeLane = releaseFastfile.match(
      /lane :distribute_testflight do \|options\|([\s\S]*?)\n {2}end/,
    )?.[0];

    expect(distributeLane).toBeDefined();
    expect(distributeLane).toContain('skip_waiting_for_build_processing: false');
    expect(distributeLane).toContain('distribute_only: true');
    expect(distributeLane).toContain('groups:');

    const deployWorkflow = readFileSync(deployWorkflowPath, 'utf8');
    expect(deployWorkflow).toContain('timeout-minutes: 90');
    expect(deployWorkflow).toContain('fastlane distribute_testflight');
    expect(deployWorkflow).toContain('resume_only');
  });

  it('does not embed Swift source as an app extension', () => {
    const project = readFileSync(projectPath, 'utf8');

    expect(project).not.toContain('Embed Foundation Extensions');
    expect(project).not.toContain('LiquidGlassCTAButton.swift in Embed Foundation Extensions');
  });
});
