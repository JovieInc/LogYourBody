import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const fastfilePath = `${repoRoot}/apps/ios/fastlane/Fastfile`;
const releaseFastfilePath = `${repoRoot}/apps/ios/fastlane/Fastfile.release`;
const projectPath = `${repoRoot}/apps/ios/LogYourBody.xcodeproj/project.pbxproj`;
const deployWorkflowPath = `${repoRoot}/.github/workflows/ios-testflight-deploy.yml`;

describe('TestFlight distribution guard', () => {
  it('executes the resume lane with an explicit platform, exact build, and no IPA upload', () => {
    const helper = readFileSync(fastfilePath, 'utf8').match(
      / {2}testflight_upload_options = lambda do \|[\s\S]*?\n {2}end/,
    )?.[0];
    const lane = readFileSync(releaseFastfilePath, 'utf8').match(
      / {2}lane :distribute_testflight do \|options\|[\s\S]*?\n {2}end/,
    )?.[0];
    expect(helper).toBeDefined();
    expect(lane).toBeDefined();
    const directory = mkdtempSync(`${tmpdir()}/lyb-testflight-resume-`);
    const sourcePath = `${directory}/resume.rb`;
    // Execute the unchanged Ruby source; only the external Fastlane actions are stubbed.
    writeFileSync(
      sourcePath,
      [
        'app_identifier = -> { "com.logyourbody.app" }',
        'app_store_app_id = -> { "6755209876" }',
        helper,
        lane,
      ].join('\n'),
    );
    try {
      const result = JSON.parse(
        execFileSync(
          'ruby',
          [
            '-rjson',
            '-rcoverage',
            '-e',
            `
        module UI
          def self.user_error!(message); raise ArgumentError, message; end
        end
        def desc(*); end
        def lane(name, &block); $resume = block; end
        def setup_app_store_connect_api; $auth_calls += 1; end
        def upload_to_testflight(**options); $uploads << options; end
        Coverage.start
        load ARGV.fetch(0)
        results = JSON.parse(STDIN.read, symbolize_names: true).map do |options|
          $auth_calls = 0
          $uploads = []
          error = nil
          begin
            $resume.call(options)
          rescue ArgumentError => exception
            error = exception.message
          end
          { uploads: $uploads, auth_calls: $auth_calls, error: error }
        end
        coverage = Coverage.result.fetch(ARGV.fetch(0)).drop(2).compact
        puts JSON.generate(results: results, covered: coverage.count { |count| count > 0 }, total: coverage.length)
      `,
            sourcePath,
          ],
          {
            encoding: 'utf8',
            input: JSON.stringify([
              {
                version_name: ' 1.2.0 ',
                build_number: ' 20260904212136 ',
                groups: 'Production Testers',
                changelog: 'Existing build',
              },
              { version_name: '1.2.0', build_number: '20260904212136' },
              { version_name: ' ', build_number: '20260904212136' },
              { version_name: '1.2.0', build_number: '' },
              { build_number: '20260904212136' },
            ]),
            timeout: 10_000,
          },
        ),
      );
      expect(result.results[0]).toEqual({
        auth_calls: 1,
        error: null,
        uploads: [
          {
            app_identifier: 'com.logyourbody.app',
            apple_id: '6755209876',
            app_platform: 'ios',
            team_id: process.env.APPLE_TEAM_ID ?? null,
            groups: ['Production Testers'],
            changelog: 'Existing build',
            distribute_external: true,
            distribute_only: true,
            skip_waiting_for_build_processing: false,
            app_version: '1.2.0',
            build_number: '20260904212136',
          },
        ],
      });
      expect(result.results[1].uploads[0].groups).toEqual(['Beta Testers']);
      expect(result.results[1].uploads[0]).not.toHaveProperty('ipa');
      for (const [index, field] of [
        [2, 'version_name'],
        [3, 'build_number'],
        [4, 'version_name'],
      ] as const) {
        expect(result.results[index].uploads).toEqual([]);
        expect(result.results[index].error).toContain(`${field} is required`);
      }
      console.log(
        `TestFlight resume Ruby coverage: ${result.covered}/${result.total} executable lines; 5 behavior cases`,
      );
      expect(result.total).toBeGreaterThan(15);
      expect(result.covered).toBe(result.total);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('waits for processing before assigning tester groups', () => {
    const fastfile = readFileSync(fastfilePath, 'utf8');
    const uploadOptions = fastfile.match(
      /testflight_upload_options = lambda do \|[\s\S]*?skip_waiting_for_build_processing: false[\s\S]*?\n {2}end/,
    )?.[0];

    expect(uploadOptions).toBeDefined();
    expect(uploadOptions).toContain('groups: groups');
    expect(uploadOptions).toContain('distribute_external: distribute_external');
    expect(uploadOptions).toContain(
      'skip_waiting_for_build_processing: skip_waiting_for_build_processing',
    );

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
