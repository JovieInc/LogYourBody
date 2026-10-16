"""Failure-path tests for the exact portable native coverage checker."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import textwrap
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ratchet", Path(__file__).with_name("native-coverage-ratchet.py"))
ratchet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ratchet)


class NativeCoverageRatchetTests(unittest.TestCase):
    def setUp(self):
        self.sha = "a" * 40
        self.selector = ratchet.SELECTORS["quality-unit"]
        self.required = "RiskTests/testAccountSwitchKeepsOtherAccountUnchanged()"
        self.files = ["Services/A.swift", "Services/B.swift"]
        self.target = {"name": "LogYourBody.app", "coveredLines": 20, "executableLines": 40, "lineCoverage": .5,
                       "files": [{"path": "/runner/apps/ios/LogYourBody/" + p, "coveredLines": 10, "executableLines": 20} for p in self.files]}
        self.report = {"targets": [self.target]}
        self.evidence = {"status": "passed", "evidenceKind": "unit_tests", "sourceRevision": self.sha,
                         "sourcePatchSha256": ratchet.EMPTY_PATCH,
                         "tests": [{"identifier": self.required, "result": "Passed"},
                                   {"identifier": "ProviderTests/testRequiresDedicatedAccount()", "result": "Skipped"}]}
        self.baseline = {"schemaVersion": 1, "target": "LogYourBody.app", "longTermTargetPercent": 70,
                         "appSourceFiles": self.files,
                         "profiles": {name: {"selector": selector, "coveredLines": 20, "executableLines": 40,
                                             "requiredTests": [self.required]} for name, selector in ratchet.SELECTORS.items()}}

    def check(self, report=None, evidence=None, baseline=None, profile="quality-unit", sha=None, selector=None, tracked=None, extra=()):
        raw = json.dumps(self.report if report is None else report).encode()
        receipt = copy.deepcopy(self.evidence if evidence is None else evidence)
        receipt.setdefault("coverageSha256", hashlib.sha256(raw).hexdigest())
        return ratchet.validate(raw, receipt, self.baseline if baseline is None else baseline,
                                profile, self.sha if sha is None else sha, self.selector if selector is None else selector,
                                set(self.files) if tracked is None else tracked, extra)

    def rejected(self, **kwargs):
        with self.assertRaises((ValueError, KeyError, TypeError)):
            self.check(**kwargs)

    def test_accepts_real_app_counts_and_reports_skips_as_unverified(self):
        result = self.check()
        self.assertEqual((result["coveredLines"], result["executableLines"]), (20, 40))
        self.assertEqual((result["passedCases"], result["skippedCases"]), (1, 1))
        self.assertIn("unverified", result["meaning"])

    def test_profiles_are_not_interchangeable(self):
        self.rejected(profile="unit-tier")
        result = self.check(profile="unit-tier", selector=ratchet.SELECTORS["unit-tier"])
        self.assertEqual(result["profile"], "unit-tier")
        for selector in [{}, {**self.selector, "onlyTesting": "OtherTests"}]:
            self.rejected(selector=selector)

    def test_baseline_schema_and_target_are_fail_closed(self):
        for key, value in [("schemaVersion", 2), ("target", "All targets")]:
            b = copy.deepcopy(self.baseline); b[key] = value
            self.rejected(baseline=b)
        b = copy.deepcopy(self.baseline); b["profiles"]["quality-unit"]["selector"] = {}
        self.rejected(baseline=b)

    def test_stale_dirty_or_nonpassing_source_proof_is_rejected(self):
        for key, value in [("sourceRevision", "b" * 40), ("status", "failed"),
                           ("evidenceKind", "fixture_ui"), ("sourcePatchSha256", "dirty")]:
            e = copy.deepcopy(self.evidence); e[key] = value
            self.rejected(evidence=e)
        self.rejected(sha="short")
        self.rejected(sha="z" * 40)

    def test_report_digest_cannot_be_substituted(self):
        e = copy.deepcopy(self.evidence); e["coverageSha256"] = "wrong"
        self.rejected(evidence=e)

    def test_missing_duplicate_or_aggregate_target_is_rejected(self):
        for targets in [[], [self.target, self.target], [{**self.target, "name": "All targets"}]]:
            self.rejected(report={"targets": targets})

    def test_invalid_counts_and_nonfinite_or_inconsistent_ratios_are_rejected(self):
        for covered, executable in [(True, 40), (20.0, 40), (-1, 40), (41, 40), (0, 0)]:
            t = copy.deepcopy(self.target);t.update(coveredLines=covered, executableLines=executable)
            self.rejected(report={"targets": [t]})
        for ratio in [None, True, float("nan"), float("inf"), .6]:
            t = copy.deepcopy(self.target);t["lineCoverage"] = ratio
            self.rejected(report={"targets": [t]})

    def test_no_filtered_or_duplicate_files_can_change_denominator(self):
        for files in [[], [self.target["files"][0]] * 2,
                      [{**self.target["files"][0], "path": "/SDK/ThirdParty.swift"}, self.target["files"][1]]]:
            t = copy.deepcopy(self.target);t["files"] = files
            self.rejected(report={"targets": [t]})

    def test_retained_sources_must_remain_in_report_even_if_totals_look_valid(self):
        t = copy.deepcopy(self.target);t["files"][1]["path"] = "/runner/apps/ios/LogYourBody/Services/C.swift"
        self.rejected(report={"targets": [t]})
        # Actual source deletion is a legitimate denominator change, not a report exclusion.
        self.check(report={"targets": [t]}, tracked={"Services/A.swift", "Services/C.swift"})

    def test_missing_duplicate_failed_and_import_only_cases_do_not_qualify(self):
        for tests in [[], [self.evidence["tests"][0]] * 2,
                      [{"identifier": "", "result": "Passed"}],
                      [{"identifier": self.required, "result": "Failed"}],
                      [{"identifier": self.required, "result": "Skipped"}],
                      [{"identifier": "ImportTests/testLoadsModule()", "result": "Passed"}]]:
            e = copy.deepcopy(self.evidence);e["tests"] = tests
            self.rejected(evidence=e)
        self.rejected(extra=["ChangedRiskTests/testNewFailurePath()"])
        b = copy.deepcopy(self.baseline);b["profiles"]["quality-unit"]["requiredTests"] = []
        self.rejected(baseline=b)

    def test_one_line_drop_fails_without_percentage_rounding(self):
        t = copy.deepcopy(self.target);t["coveredLines"] = 19;t["lineCoverage"] = 19 / 40;t["files"][0]["coveredLines"] = 9
        self.rejected(report={"targets": [t]})
        t["coveredLines"] = 21;t["lineCoverage"] = 21 / 40;t["files"][0]["coveredLines"] = 11
        self.assertEqual(self.check(report={"targets": [t]})["coveredLines"], 21)

    def test_baseline_edit_cannot_lower_floor_change_selector_or_drop_required_cases(self):
        ratchet.validate_baseline_change(self.baseline, self.baseline, set(self.files))
        for mutate in [lambda b: b.update(target="Other"), lambda b: b.update(longTermTargetPercent=69),
                       lambda b: b["profiles"].pop("unit-tier"),
                       lambda b: b["profiles"]["quality-unit"].update(selector={}),
                       lambda b: b["profiles"]["quality-unit"].update(coveredLines=19),
                       lambda b: b["profiles"]["quality-unit"].update(requiredTests=[])]:
            b = copy.deepcopy(self.baseline);mutate(b)
            with self.assertRaises(ValueError):
                ratchet.validate_baseline_change(b, self.baseline, set(self.files))
        b = copy.deepcopy(self.baseline);b["appSourceFiles"] = self.files[:1]
        with self.assertRaises(ValueError):
            ratchet.validate_baseline_change(b, self.baseline, set(self.files))
        ratchet.validate_baseline_change(b, self.baseline, {self.files[0]})

    def run_cli(self, *, expected=None, previous=False, malformed=False, missing=False, lowered=False, base=None):
        with tempfile.TemporaryDirectory() as directory:
            r = Path(directory); raw = json.dumps(self.report).encode(); e = copy.deepcopy(self.evidence)
            e["coverageSha256"] = hashlib.sha256(raw).hexdigest()
            (r / "coverage.json").write_bytes(raw)
            (r / "evidence.json").write_text("{" if malformed else json.dumps(e))
            (r / "baseline.json").write_text(json.dumps(self.baseline))
            args = ["ratchet", "--coverage", str(r / ("missing" if missing else "coverage.json")),
                    "--evidence", str(r / "evidence.json"), "--baseline", str(r / "baseline.json"),
                    "--profile", "quality-unit", "--source-sha", self.sha, "--source-root", str(r),
                    "--base-revision", base or "b" * 40,
                    "--scheme", "LogYourBody", "--only-testing", "LogYourBodyTests", "--required-test", self.required]
            old = copy.deepcopy(self.baseline)
            if lowered:old["profiles"]["quality-unit"]["coveredLines"] = 21
            git_output = [expected or self.sha, "\n".join(ratchet.APP_PREFIX + p for p in self.files)]
            git_output += [base or "b" * 40, "scripts/ios/native-coverage-baseline.json" if previous else ""]
            if previous:git_output += [json.dumps(old)]
            with patch.object(sys, "argv", args), patch.object(ratchet.subprocess, "check_output", side_effect=git_output), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return ratchet.main()

    def test_cli_checks_the_actual_checkout_and_reads_previous_baseline(self):
        self.assertEqual(self.run_cli(), 0)
        self.assertEqual(self.run_cli(previous=True), 0)
        self.assertEqual(self.run_cli(previous=True, lowered=True), 65)
        self.assertEqual(self.run_cli(base="not-a-sha"), 65)
        self.assertEqual(self.run_cli(expected="b" * 40), 65)
        self.assertEqual(self.run_cli(malformed=True), 65)
        self.assertEqual(self.run_cli(missing=True), 65)


    def test_comparison_base_uses_trusted_main_across_actual_git_event_shapes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.STDOUT).strip()
            git("init", "-q", "-b", "main")
            git("config", "user.name", "Coverage Fixture")
            git("config", "user.email", "coverage-fixture@example.invalid")
            # Synthetic history must not invoke the developer's hardware or password-manager signer.
            git("config", "commit.gpgSign", "false")
            (root / "base").write_text("base")
            git("add", "."); git("commit", "-qm", "common baseline")
            common = git("rev-parse", "HEAD")
            git("switch", "-qc", "draft")
            (root / "draft").write_text("draft")
            git("add", "."); git("commit", "-qm", "draft diverges")
            draft = git("rev-parse", "HEAD")
            git("switch", "-q", "main")
            (root / "raised-baseline").write_text("higher floor on canonical main")
            git("add", "."); git("commit", "-qm", "raise canonical baseline")
            canonical = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/origin/main", canonical)
            for event in ("PR divergence", "direct 172 dispatch", "Mac-child dispatch"):
                with self.subTest(event=event):
                    self.assertEqual(ratchet.resolve_comparison_base(root, draft, ""), canonical)
                    self.assertNotEqual(ratchet.resolve_comparison_base(root, draft, ""), common)
            self.assertEqual(ratchet.resolve_comparison_base(root, draft, canonical), canonical)
            self.assertEqual(ratchet.resolve_comparison_base(root, canonical, common), common)
            self.assertEqual(ratchet.resolve_comparison_base(root, canonical, ""), common)
            git("switch", "-q", "draft")
            git("merge", "--no-ff", "-qm", "synthetic merge group", "main")
            group = git("rev-parse", "HEAD")
            self.assertEqual(ratchet.resolve_comparison_base(root, group, canonical), canonical)
            with self.assertRaises(ValueError):
                ratchet.resolve_comparison_base(root, draft, "invalid")
            with self.assertRaises(subprocess.CalledProcessError):
                ratchet.resolve_comparison_base(root, draft, "f" * 40)
            git("update-ref", "-d", "refs/remotes/origin/main")
            with self.assertRaises(subprocess.CalledProcessError):
                ratchet.resolve_comparison_base(root, draft, "")

    def test_actual_native_call_sites_propagate_failure_and_guard_absent_output(self):
        repo = Path(__file__).resolve().parents[2]
        unit = (repo / ".github/workflows/ios-unit.yml").read_text()
        quality = (repo / ".github/workflows/ios-quality.yml").read_text()
        audit = (repo / "scripts/ios/launch-quality-audit.sh").read_text()
        for workflow in (unit, quality):
            self.assertIn("fetch-depth: 0", workflow)
            self.assertIn("github.event.pull_request.base.sha || github.event.merge_group.base_sha || github.event.before", workflow)
        self.assertIn("always() && runner.environment == 'github-hosted' && env.UNIT_RESULTS != ''", unit)
        self.assertIn("if: always() && env.UNIT_RESULTS != ''", unit)
        self.assertIn('find "${UNIT_RESULTS:?}"', unit)
        self.assertIn('${{ env.UNIT_RESULTS }}/unit-tier.log', unit)
        self.assertIn('"$ARTIFACT_DIR/launch-quality-unit-tests.xcresult" --require-biometric-coverage', audit)
        self.assertIn("OnboardingGoldenPathUITests/testBodyScoreOnboardingGoldenPathReachesReveal", audit)
        block = unit.split("      - name: Unit-tier tests and native coverage ratchet\n", 1)[1].split("\n      - name:", 1)[0]
        block = textwrap.dedent(block.split("        run: |\n", 1)[1])
        self.assertIn("--export-coverage", block)
        self.assertNotIn("--require-biometric-coverage", block)
        self.assertIn("--scheme LogYourBodyTiers --test-plan Unit", block)
        quality_call = audit.split('python3 "$ROOT_DIR/scripts/ios/native-coverage-ratchet.py"', 1)[1].split("\n\n", 1)[0]
        quality_call = 'python3 "$ROOT_DIR/scripts/ios/native-coverage-ratchet.py"' + quality_call
        for native_status, collector_status, checker_status, expected, expected_calls in (
                (0, 0, 0, 0, 2), (41, 0, 0, 41, 0), (0, 66, 0, 66, 1), (0, 0, 65, 65, 2)):
            with self.subTest(native=native_status, collector=collector_status, checker=checker_status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); tools = root / "tools"; tools.mkdir()
                (root / "apps/ios").mkdir(parents=True)
                (root / "scripts/ios").mkdir(parents=True)
                (root / "scripts/ios/resolve-simulator-destination.sh").write_text("echo platform=iOS-Simulator\n")
                git = tools / "git"
                git.write_text('#!/bin/sh\ncase "$*" in *rev-parse*) printf "' + self.sha + '\\n";; esac\n')
                python = tools / "python3"
                python.write_text("#!" + sys.executable + "\nimport os,sys,json\nwith open(os.environ['CALL_LOG'],'a') as log:log.write(json.dumps(sys.argv[1:])+'\\n')\nsys.exit(int(os.environ['CHECKER_STATUS'] if 'native-coverage-ratchet.py' in sys.argv[1] else os.environ['COLLECTOR_STATUS']))\n")
                bundle = tools / "bundle"
                bundle.write_text("#!" + sys.executable + "\nimport os,sys\nfrom pathlib import Path\nout=next(a.split(':',1)[1] for a in sys.argv if a.startswith('output_directory:'))\nPath(out,'Unit.xcresult').mkdir()\nprint('retained native output')\nsys.exit(int(os.environ['NATIVE_STATUS']))\n")
                for tool in (git, python, bundle):tool.chmod(0o755)
                env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                       "GITHUB_WORKSPACE": str(root), "GITHUB_RUN_ID": "fixture", "GITHUB_RUN_ATTEMPT": "1",
                       "GITHUB_ENV": str(root / "github-env"), "CALL_LOG": str(root / "calls"),
                       "NATIVE_STATUS": str(native_status), "COLLECTOR_STATUS": str(collector_status),
                       "CHECKER_STATUS": str(checker_status), "BASE_SHA": self.sha}
                result = subprocess.run(["bash", "-eo", "pipefail", "-c", block + "\nprintf AFTER_GATE"], cwd=root, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                calls = (root / "calls").read_text().splitlines() if (root / "calls").exists() else []
                self.assertEqual(len(calls), expected_calls)
                self.assertEqual("AFTER_GATE" in result.stdout, expected == 0)
                output = root / "apps/ios/test_results/unit-tier/fixture-1"
                self.assertIn("retained native output", (output / "unit-tier.log").read_text())
                if expected_calls == 2:
                    args = json.loads(calls[-1])
                    self.assertIn("unit-tier", args);self.assertIn("LogYourBodyTiers", args);self.assertIn("Unit", args)
                env.update(ROOT_DIR=str(root), ARTIFACT_DIR=str(root), SCHEME="LogYourBody", CHECKER_STATUS="65")
                result = subprocess.run(["bash", "-eo", "pipefail", "-c", quality_call + "\nprintf AFTER_GATE"], cwd=root, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
                self.assertNotIn("AFTER_GATE", result.stdout)

    def test_unit_tier_export_collects_raw_coverage_without_new_function_floor(self):
        path = Path(__file__).with_name("launch-quality-evidence.py")
        spec = importlib.util.spec_from_file_location("coverage_export", path)
        exporter = importlib.util.module_from_spec(spec);spec.loader.exec_module(exporter)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);bundle = root / "Unit.xcresult";bundle.mkdir()
            (root / "source-revision.txt").write_text(self.sha)
            (root / "source-working-tree.patch").write_bytes(b"")
            payload = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": self.required, "result": "Passed"}]}
            args = ["export", "--bundle", str(bundle), "--started-at", "0", "--export-coverage"]
            raw = json.dumps(self.report)
            with patch.object(sys, "argv", args), patch.object(exporter.subprocess, "check_output", side_effect=[json.dumps(payload), raw]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(exporter.main(), 0)
            evidence = json.loads(bundle.with_suffix(".evidence.json").read_text())
            self.assertEqual(evidence["requiredFunctionCoverage"], [])
            self.assertEqual(evidence["coverageSha256"], hashlib.sha256(bundle.with_suffix(".coverage.json").read_bytes()).hexdigest())
            self.assertEqual(evidence["sourceRevision"], self.sha)
            with patch.object(sys, "argv", args), patch.object(exporter.subprocess, "check_output", side_effect=[json.dumps(payload), subprocess.CalledProcessError(1, "xccov")]), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(exporter.main(), 65)
            self.assertFalse(bundle.with_suffix(".evidence.json").exists())


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(NativeCoverageRatchetTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"Native coverage ratchet behavior tests executed: {result.testsRun}")
    sys.exit(0 if result.wasSuccessful() else 1)
