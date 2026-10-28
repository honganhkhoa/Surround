#!/usr/bin/env python3
"""Supervisor regression tests use fake xcodebuild and xcrun only, never a real simulator."""

import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "supervise-ipad-ui-test-part.py"
spec = importlib.util.spec_from_file_location("supervise_part", SCRIPT)
supervise = importlib.util.module_from_spec(spec)
spec.loader.exec_module(supervise)
UDID = "11111111-2222-3333-4444-555555555555"
CRASHED = "MessagesNavigationUITests/testInitialThreeMessageOpeningStaysAboveComposerWithoutInput()"
SELECTOR = "SurroundUITests/MessagesNavigationUITests/testInitialThreeMessageOpeningStaysAboveComposerWithoutInput"
# The failure CI run 40157450049 recorded when SimRenderServer crashed.
CRASH_SUMMARY = {
    "result": "Failed", "failedTests": 1, "passedTests": 15, "skippedTests": 6,
    "testFailures": [{
        "failureText": "Test crashed with signal term.",
        "targetName": "SurroundUITests",
        "testIdentifier": 11,
        "testIdentifierString": CRASHED,
        "testName": "testInitialThreeMessageOpeningStaysAboveComposerWithoutInput()",
    }],
}
ASSERTION_SUMMARY = {
    "result": "Failed", "failedTests": 1,
    "testFailures": [{"failureText": "XCTAssertTrue failed - Initial wide opening must leave the inbox search visible and usable.",
                      "targetName": "SurroundUITests",
                      "testIdentifierString": "MessagesNavigationUITests/testInitialTwoMessageOpeningStaysAboveComposerWithoutInput()"}],
}
QUERY_TIMED_OUT = "MessagesNavigationUITests/testMessagesSearchLoadingFailureAndRetryKeepNavigationStable()"
QUERY_SELECTOR = "SurroundUITests/MessagesNavigationUITests/testMessagesSearchLoadingFailureAndRetryKeepNavigationStable"
# The failure and console line CI run 40462251724 recorded when a UI query stalled.
QUERY_TIMEOUT_SUMMARY = {
    "result": "Failed", "failedTests": 1, "passedTests": 14, "skippedTests": 6,
    "testFailures": [{
        "failureText": "Failed to resolve query: Timed out while evaluating UI query.",
        "targetName": "SurroundUITests",
        "testIdentifierString": QUERY_TIMED_OUT,
        "testName": "testMessagesSearchLoadingFailureAndRetryKeepNavigationStable()",
    }],
}
QUERY_TIMEOUT_CONSOLE = ("Test Case '-[SurroundUITests.MessagesNavigationUITests "
                         "testMessagesSearchLoadingFailureAndRetryKeepNavigationStable]' failed (129.486 seconds).")
PASSED_SUMMARY = {"result": "Passed", "failedTests": 0, "passedTests": 1, "testFailures": []}
EMPTY_SUMMARY = {"result": "Passed", "failedTests": 0, "passedTests": 0, "testFailures": []}
SIM_RENDER_REPORT = {
    "name": "SimRenderServer-2026-10-25-033542.ips",
    "header": {"app_name": "SimRenderServer", "bug_type": "309",
               "bundleID": "com.apple.CoreSimulator.SimRenderingServices.SimRenderServer"},
    "body": {"exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
             "asi": {"libdispatch.dylib": ["BUG IN LIBDISPATCH: ulock_wake() failed", "Abort Cause 33"]}},
}
APP_REPORT = {"name": "Surround-2026-10-25-033542.ips",
              "header": {"app_name": "Surround", "bundleID": "com.honganhkhoa.Surround"}, "body": {}}
RECOVERY = ("Oct 25 03:35:22 host CoreSimulatorService[4878] <Warning>: Bundle "
            "com.apple.CoreSimulator.SimRenderingServices reported a critical error. "
            "Will attempt recovery strategy Reload Bundle.\n")

# A same-group helper stands in for xcodebuild's app-launch workers: when only
# the fake's own PID is interrupted, its handler waits on the helper and the
# supervisor has to escalate, which the deadline tests reject.
FAKE_XCODEBUILD = textwrap.dedent("""\
    import json, os, signal, subprocess, sys, time
    from pathlib import Path
    arguments = sys.argv[1:]
    bundle = arguments[arguments.index("-resultBundlePath") + 1]
    rerun = bundle.endswith("-Rerun.xcresult")
    with open(os.environ["FAKE_CALLS"], "a") as calls:
        calls.write(json.dumps(arguments) + "\\n")
    scenario = json.loads(Path(os.environ["FAKE_SCENARIO"]).read_text())["rerun" if rerun else "first"]
    with open(os.environ["FAKE_PIDS"], "a") as pids:
        pids.write("%d\\n" % os.getpid())
    worker = None
    def finish(code):
        if scenario.get("simulatorStateAfter"):
            Path(os.environ["FAKE_SIM_STATE"]).write_text(scenario["simulatorStateAfter"])
        if worker is not None:
            try:
                worker.wait(timeout=10)
            except subprocess.TimeoutExpired:
                sys.exit(99)  # Only the fake's PID was interrupted.
        if "summary" in scenario:
            Path(bundle).mkdir(parents=True)
            (Path(bundle) / "summary.json").write_text(json.dumps(scenario["summary"]))
        sys.exit(code)
    if scenario.get("interruptExit") is not None:
        signal.signal(signal.SIGINT, lambda *_: finish(scenario["interruptExit"]))
        signal.signal(signal.SIGTERM, lambda *_: finish(scenario["interruptExit"] + 13))
    for name in scenario.get("ignore", []):
        signal.signal(getattr(signal, "SIG" + name), signal.SIG_IGN)
    if scenario.get("groupWorker"):
        worker = subprocess.Popen([sys.executable, "-c",
            "import pathlib, signal, sys, time\\n"
            "signal.signal(signal.SIGINT, lambda *_: (pathlib.Path(sys.argv[1]).write_text('interrupted'), sys.exit(0)))\\n"
            "pathlib.Path(sys.argv[1] + '.ready').write_text('ready')\\n"
            "time.sleep(60)\\n", os.environ["FAKE_WORKER_MARKER"]], stdout=subprocess.DEVNULL)
        while not Path(os.environ["FAKE_WORKER_MARKER"] + ".ready").exists():
            time.sleep(0.01)
    if scenario.get("inheritStdout") or scenario.get("stubbornWorker"):
        # A group member that outlives xcodebuild: it holds stdout, or ignores SIGINT.
        sleeper = subprocess.Popen(
            [sys.executable, "-c", "import signal, time; signal.signal(signal.SIGINT, signal.SIG_IGN); time.sleep(30)"],
            stdout=None if scenario.get("inheritStdout") else subprocess.DEVNULL,
            stderr=None if scenario.get("inheritStdout") else subprocess.DEVNULL)
        Path(os.environ["FAKE_SLEEPER_PID"]).write_text(str(sleeper.pid))
    print("Test Suite 'Selected tests' started", flush=True)
    for line in scenario.get("console", []):
        print(line, flush=True)
    for report in scenario.get("reports", []):
        path = Path(os.environ["FAKE_REPORTS"]) / report["name"]
        path.write_text(json.dumps(report["header"]) + "\\n" + json.dumps(report.get("body", {})) + "\\n")
    if scenario.get("coreLog"):
        with open(os.environ["FAKE_CORE_LOG"], "a") as log:
            log.write(scenario["coreLog"])
    Path(os.environ["FAKE_READY"] + (".rerun" if rerun else "")).write_text("ready")
    deadline = time.monotonic() + scenario.get("sleep", 0)
    while time.monotonic() < deadline:
        time.sleep(0.05)
    finish(scenario["exit"])
""")

FAKE_XCRUN = textwrap.dedent("""\
    #!{python}
    import json, os, sys
    from pathlib import Path
    arguments = sys.argv[1:]
    with open(os.environ["FAKE_XCRUN_CALLS"], "a") as calls:
        calls.write(json.dumps(arguments) + "\\n")
    if arguments[:4] == ["xcresulttool", "get", "test-results", "summary"]:
        summary = Path(arguments[arguments.index("--path") + 1]) / "summary.json"
        if not summary.exists():
            sys.exit("no summary")
        print(summary.read_text())
    elif arguments[:2] == ["simctl", "boot"]:
        import time
        time.sleep(float(os.environ.get("FAKE_BOOT_SECONDS", "0")))
        code = int(os.environ.get("FAKE_BOOT_EXIT", "0"))
        after = os.environ.get("FAKE_BOOT_STATE_AFTER") or ("Booted" if code == 0 else None)
        if after:
            Path(os.environ["FAKE_SIM_STATE"]).write_text(after)
        sys.exit(code)
    elif arguments[:2] == ["simctl", "bootstatus"]:
        import time
        print("Status=4, isTerminal=NO\\n\\tWaiting on System App", flush=True)
        time.sleep(float(os.environ.get("FAKE_BOOTSTATUS_SECONDS", "0")))
        sys.exit(int(os.environ.get("FAKE_BOOTSTATUS_EXIT", "0")))
    elif arguments[:2] == ["simctl", "list"]:
        # The state file holds comma-separated states, one per listing; the last one stays.
        import time
        time.sleep(float(os.environ.get("FAKE_LIST_SECONDS", "0")))
        states = Path(os.environ["FAKE_SIM_STATE"]).read_text().split(",")
        Path(os.environ["FAKE_SIM_STATE"]).write_text(",".join(states[1:] or states))
        device = {{"udid": os.environ["FAKE_UDID"].lower(), "state": states[0]}}
        print(json.dumps({{"devices": {{"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [device]}}}}))
    elif arguments[:3] == ["simctl", "io", arguments[2]] and arguments[3] == "screenshot":
        Path(arguments[4]).write_bytes(b"fake screenshot")
    else:
        sys.exit("unexpected xcrun " + " ".join(arguments))
""").format(python=sys.executable)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


class CommandTests(unittest.TestCase):
    COMMAND = ["xcodebuild", "test-without-building", "-scheme", "Surround",
               "-only-testing:SurroundUITests", "-skip-testing", "SurroundUITests/ProfileUITests",
               "-skip-testing:SurroundUITests/SurroundUITests/testA", "-test-timeouts-enabled", "YES",
               "-resultBundlePath", "TestResults/Main-1.xcresult"]

    def test_rerun_keeps_options_and_replaces_selection_and_bundle(self):
        rerun = supervise.rerun_command(self.COMMAND, ["SurroundUITests/A/testB"],
                                        "TestResults/Main-1-Rerun.xcresult")
        self.assertEqual(rerun, ["xcodebuild", "test-without-building", "-scheme", "Surround",
                                 "-test-timeouts-enabled", "YES",
                                 "-only-testing:SurroundUITests/A/testB",
                                 "-resultBundlePath", "TestResults/Main-1-Rerun.xcresult"])

    def test_result_bundle_must_be_single_and_named(self):
        self.assertEqual(supervise.result_bundle_of(self.COMMAND), "TestResults/Main-1.xcresult")
        self.assertEqual(supervise.rerun_bundle_of("T/Main-1.xcresult"), "T/Main-1-Rerun.xcresult")
        for command in (["xcodebuild"], ["xcodebuild", "-resultBundlePath"],
                        ["xcodebuild", "-resultBundlePath", "a.xcresult", "-resultBundlePath", "b.xcresult"],
                        ["xcodebuild", "-resultBundlePath", "a.bundle"]):
            with self.assertRaises(ValueError):
                supervise.result_bundle_of(command)


class DecisionTests(unittest.TestCase):
    ATTEMPT = {"externalSignal": None, "stoppedAtDeadline": False,
               "consoleMarkers": {"executionTimeAllowanceFailures": 0}}

    def decide(self, summary=CRASH_SUMMARY, reports=("SimRenderServer",), recovered=False,
               remaining=1200, attempt=None):
        return supervise.rerun_decision(attempt or self.ATTEMPT, summary, None,
                                        [{"process": name, "bundleID": None} for name in reports],
                                        recovered, remaining, 300)

    def test_ci_crash_with_sim_render_report_reruns_only_that_test(self):
        self.assertEqual(self.decide(), ([SELECTOR], None))
        self.assertEqual(self.decide(reports=(), recovered=True), ([SELECTOR], None))

    def test_assertions_mixed_or_unidentified_failures_never_rerun(self):
        mixed = dict(CRASH_SUMMARY, failedTests=2,
                     testFailures=CRASH_SUMMARY["testFailures"] + ASSERTION_SUMMARY["testFailures"])
        unidentified = dict(CRASH_SUMMARY, testFailures=[{"failureText": "Test crashed with signal term."}])
        canceled = dict(CRASH_SUMMARY, testFailures=[dict(CRASH_SUMMARY["testFailures"][0],
                                                          failureText="Testing was canceled")])
        quoted = dict(CRASH_SUMMARY, testFailures=[dict(CRASH_SUMMARY["testFailures"][0],
                                                        failureText="XCTAssertTrue failed - Test crashed with signal term.")])
        for summary in (ASSERTION_SUMMARY, mixed, unidentified, canceled, quoted, PASSED_SUMMARY):
            tests, reason = self.decide(summary=summary)
            self.assertIsNone(tests)
            self.assertTrue(reason)

    def test_other_signals_counts_and_limits_never_rerun(self):
        segv = dict(CRASH_SUMMARY, testFailures=[dict(CRASH_SUMMARY["testFailures"][0],
                                                      failureText="Test crashed with signal segv.")])
        uncounted = dict(CRASH_SUMMARY, failedTests=2)
        many = dict(CRASH_SUMMARY, failedTests=4, testFailures=[
            dict(CRASH_SUMMARY["testFailures"][0], testIdentifierString="A/test{}()".format(index))
            for index in range(4)])
        for summary in (segv, uncounted, many):
            self.assertIsNone(self.decide(summary=summary)[0])
        killed = dict(CRASH_SUMMARY, testFailures=[dict(CRASH_SUMMARY["testFailures"][0],
                                                        failureText="Test crashed with signal kill.")])
        self.assertEqual(self.decide(summary=killed)[0], [SELECTOR])

    def test_evidence_app_crashes_timeouts_time_and_interruptions_gate_the_rerun(self):
        self.assertIn("no SimRenderServer", self.decide(reports=("ReportCrash", "backboardd"))[1])
        self.assertIn("Surround", self.decide(reports=("SimRenderServer", "Surround"))[1])
        self.assertIn("SurroundUITests-Runner", self.decide(reports=("SurroundUITests-Runner",), recovered=True)[1])
        by_bundle = supervise.rerun_decision(
            self.ATTEMPT, CRASH_SUMMARY, None,
            [{"process": "SimRenderServer", "bundleID": None},
             {"process": "Renamed", "bundleID": "com.honganhkhoa.Surround"}], False, 1200, 300)
        self.assertIn("tested process", by_bundle[1])
        timed_out = dict(self.ATTEMPT, consoleMarkers={"executionTimeAllowanceFailures": 1})
        self.assertIn("execution time allowance", self.decide(attempt=timed_out)[1])
        self.assertIn("remain", self.decide(remaining=120)[1])
        self.assertIn("deadline", self.decide(attempt=dict(self.ATTEMPT, stoppedAtDeadline=True))[1])
        self.assertIn("interrupted", self.decide(attempt=dict(self.ATTEMPT, externalSignal=15))[1])
        self.assertIn("could not be read", supervise.rerun_decision(
            self.ATTEMPT, None, "no result bundle", [], True, 1200, 300)[1])


    def query_timeout(self, text, identifier=QUERY_TIMED_OUT):
        return dict(QUERY_TIMEOUT_SUMMARY, testFailures=[dict(QUERY_TIMEOUT_SUMMARY["testFailures"][0],
                                                              failureText=text, testIdentifierString=identifier)])

    def test_query_timeouts_rerun_without_crash_evidence_in_their_measured_time(self):
        timed = dict(self.ATTEMPT, failedTestSeconds={QUERY_SELECTOR: 129.486})
        for text in ("Failed to resolve query: Timed out while evaluating UI query.",
                     "Failed to get matching snapshots: Timed out while evaluating UI query.",
                     "Failed to get matching snapshot: Timed out while evaluating UI query."):
            self.assertEqual(self.decide(summary=self.query_timeout(text), reports=(), attempt=timed),
                             ([QUERY_SELECTOR], None))
        # CI's run had 239 s left: enough for xcodebuild's overhead and the 129-s test, not the 300-s floor.
        self.assertEqual(self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=(), remaining=239, attempt=timed),
                         ([QUERY_SELECTOR], None))
        tests, reason = self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=(), remaining=220, attempt=timed)
        self.assertIsNone(tests)
        self.assertIn("the rerun needs 229 s", reason)
        # Without a measured duration it needs the floor.
        self.assertIn("needs 300 s", self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=(), remaining=239)[1])
        self.assertEqual(self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=(), remaining=300)[0],
                         [QUERY_SELECTOR])

    def test_app_hangs_and_quoted_timeouts_never_rerun(self):
        for text in ("Failed to get matching snapshots: Unable to perform work on main run loop, "
                     "process main thread busy for 30.0s",
                     "XCTAssertTrue failed - Failed to resolve query: Timed out while evaluating UI query.",
                     "Failed to resolve query: Timed out while evaluating UI query. Retrying"):
            tests, reason = self.decide(summary=self.query_timeout(text), reports=())
            self.assertIsNone(tests, text)
            self.assertIn("failed with", reason)

    def test_query_timeouts_keep_the_other_gates(self):
        self.assertIn("Surround", self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=("Surround",))[1])
        timed_out = dict(self.ATTEMPT, consoleMarkers={"executionTimeAllowanceFailures": 1})
        self.assertIn("execution time allowance",
                      self.decide(summary=QUERY_TIMEOUT_SUMMARY, reports=(), attempt=timed_out)[1])
        mixed = dict(QUERY_TIMEOUT_SUMMARY, failedTests=2,
                     testFailures=QUERY_TIMEOUT_SUMMARY["testFailures"] + ASSERTION_SUMMARY["testFailures"])
        self.assertIn("XCTAssertTrue failed", self.decide(summary=mixed, reports=())[1])
        many = dict(QUERY_TIMEOUT_SUMMARY, failedTests=4, testFailures=[
            dict(QUERY_TIMEOUT_SUMMARY["testFailures"][0], testIdentifierString="A/test{}()".format(index))
            for index in range(4)])
        self.assertIn("more than the 3", self.decide(summary=many, reports=())[1])

    def test_a_crash_beside_a_query_timeout_still_needs_crash_evidence_and_the_floor(self):
        both = dict(CRASH_SUMMARY, failedTests=2,
                    testFailures=CRASH_SUMMARY["testFailures"] + QUERY_TIMEOUT_SUMMARY["testFailures"])
        self.assertIn("no SimRenderServer", self.decide(summary=both, reports=())[1])
        timed = dict(self.ATTEMPT, failedTestSeconds={QUERY_SELECTOR: 129.486, SELECTOR: 20})
        self.assertEqual(self.decide(summary=both, attempt=timed), (sorted([SELECTOR, QUERY_SELECTOR]), None))
        self.assertIn("needs 300 s", self.decide(summary=both, attempt=timed, remaining=299)[1])
        # The crashed test's duration is cut short; the floor stands in for it.
        long = dict(self.ATTEMPT, failedTestSeconds={QUERY_SELECTOR: 400, SELECTOR: 20})
        self.assertIn("needs 500 s", self.decide(summary=both, attempt=long, remaining=450)[1])
        self.assertIn("needs 300 s", self.decide(remaining=299, attempt=long)[1])


class EvidenceTests(unittest.TestCase):
    def test_reports_are_described_from_header_body_or_file_name(self):
        with tempfile.TemporaryDirectory() as directory:
            full = Path(directory) / "Renamed.ips"
            full.write_text(json.dumps(SIM_RENDER_REPORT["header"]) + "\n" + json.dumps(SIM_RENDER_REPORT["body"]))
            described = supervise.describe_report(str(full))
            self.assertEqual(described["process"], "SimRenderServer")
            self.assertEqual(described["exception"], "EXC_BREAKPOINT SIGTRAP")
            self.assertEqual(described["reason"], "BUG IN LIBDISPATCH: ulock_wake() failed; Abort Cause 33")
            for name, process in (("SurroundUITests-Runner-2026-10-25-033542-2.ips", "SurroundUITests-Runner"),
                                  ("Surround-2026-10-25-033542.000.ips", "Surround")):
                path = Path(directory) / name
                path.write_text("{not json")
                described = supervise.describe_report(str(path))
                self.assertEqual(described["process"], process)
                self.assertTrue(supervise.is_tested_process(described))

    def test_new_reports_ignore_reports_that_existed_before_the_run(self):
        with tempfile.TemporaryDirectory() as directory:
            old = Path(directory) / "Surround-2026-10-24-000000.ips"
            old.write_text("{}")
            os.utime(old, (time.time() - 3600, time.time() - 3600))
            before = supervise.report_snapshot([directory])
            started = time.time()
            new = Path(directory) / "SimRenderServer-2026-10-25-033542.ips"
            new.write_text("{}")
            self.assertEqual(supervise.new_reports([directory, directory + "/missing"], before, started),
                             [str(new)])

    def test_report_copy_limit_lists_reports_it_does_not_copy(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(supervise, "REPORT_COPY_LIMIT", 10):
            paths = []
            for name in ("SimRenderServer-2026-10-25-033542.ips", "backboardd-2026-10-25-033543.ips"):
                path = Path(directory) / name
                path.write_text("123456")
                paths.append(str(path))
            reports = supervise.copy_reports(paths, Path(directory) / "copies")
            self.assertEqual([report["copied"] for report in reports], [True, False])
            self.assertEqual([path.name for path in (Path(directory) / "copies").iterdir()],
                             ["SimRenderServer-2026-10-25-033542.ips"])

    def test_log_scan_keeps_recovery_and_latest_lines_and_drops_noise(self):
        identity = "CoreSimulatorService[4878] <Error>: Failed to get a device identity for {}\n".format(UDID)
        state = 'Error Domain=com.apple.CoreSimulator.SimError Code=405 "Unable to lookup in current state: Shutting Down"\n'
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(supervise, "LOG_EXCERPT_LIMIT", 256), \
                mock.patch.object(supervise, "LOG_KEEP_LIMIT", len(state) * 2):
            log = Path(directory) / "CoreSimulator.log"
            log.write_text("before the run\n")
            start = supervise.log_position(str(log))
            with open(log, "a") as stream:
                stream.write("notice before the crash\n")
                stream.write(identity * 3000)
                stream.write(state * 5)
                stream.write("".join("filler line {}\n".format(index) for index in range(100)))
                stream.write(RECOVERY + identity + "last line\n")
            recovered, excerpt, counts = supervise.scan_core_simulator_log(str(log), start)
            self.assertTrue(recovered)
            self.assertNotIn("before the run", excerpt)
            self.assertNotIn("notice before the crash", excerpt)
            self.assertNotIn("device identity", excerpt)
            self.assertTrue(excerpt.startswith(state * 2))
            self.assertTrue(excerpt.endswith("filler line 99\n" + RECOVERY + "last line\n"))
            self.assertEqual(counts["noiseLinesOmitted"], 3001)
            self.assertGreater(counts["linesOverLimit"], 3)

    def test_log_scan_reads_a_rotated_log_from_its_start(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "CoreSimulator.log"
            log.write_text("before the run\n" * 20)
            start = supervise.log_position(str(log))
            rotated = Path(directory) / "new.log"
            rotated.write_text(RECOVERY + "filler\n" * 100)  # Larger than the old offset.
            os.replace(rotated, log)
            self.assertTrue(supervise.scan_core_simulator_log(str(log), start)[0])
            self.assertFalse(supervise.scan_core_simulator_log(str(log) + ".missing", None)[0])


class SupervisorProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "bin").mkdir()
        (self.root / "reports").mkdir()
        (self.root / "TestResults").mkdir()
        self.core_log = self.root / "CoreSimulator.log"
        self.core_log.write_text("before the run\n")
        xcrun = self.root / "bin" / "xcrun"
        xcrun.write_text(FAKE_XCRUN)
        xcrun.chmod(0o755)
        (self.root / "xcodebuild.py").write_text(FAKE_XCODEBUILD)
        self.bundle = str(self.root / "TestResults" / "SurroundUITests-iPad-Messages-1.xcresult")
        self.diagnostics = self.root / "TestResults" / "SurroundUITests-iPad-Messages-1-Diagnostics"
        self.worker_marker = self.root / "worker-interrupted"
        self.ready = self.root / "ready"
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                        FAKE_CALLS=str(self.root / "calls.jsonl"), FAKE_XCRUN_CALLS=str(self.root / "xcrun.jsonl"),
                        FAKE_SCENARIO=str(self.root / "scenario.json"), FAKE_REPORTS=str(self.root / "reports"),
                        FAKE_CORE_LOG=str(self.core_log), FAKE_WORKER_MARKER=str(self.worker_marker),
                        FAKE_READY=str(self.ready), FAKE_SLEEPER_PID=str(self.root / "sleeper.pid"),
                        FAKE_PIDS=str(self.root / "fake.pids"), FAKE_SIM_STATE=str(self.root / "sim-state"),
                        FAKE_UDID=UDID, PYTHONDONTWRITEBYTECODE="1")
        (self.root / "sim-state").write_text("Booted")

    def tearDown(self):
        # Each fake xcodebuild leads its own process group, as the real one does.
        pids = self.root / "fake.pids"
        for pid in (pids.read_text().split() if pids.exists() else []):
            try:
                os.killpg(int(pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        sleeper = self.root / "sleeper.pid"
        if sleeper.exists() and alive(int(sleeper.read_text())):
            os.kill(int(sleeper.read_text()), signal.SIGKILL)
        self.temporary.cleanup()

    def command(self, deadline=600, min_rerun=0, interrupt_grace=5):
        return [sys.executable, str(SCRIPT), "--simulator", UDID, "--deadline-seconds", str(deadline),
                "--diagnostics", str(self.diagnostics), "--min-rerun-seconds", str(min_rerun),
                "--interrupt-grace-seconds", str(interrupt_grace), "--terminate-grace-seconds", "0.5",
                "--report-directory", str(self.root / "reports"),
                "--core-simulator-log", str(self.core_log), "--",
                sys.executable, str(self.root / "xcodebuild.py"), "test-without-building",
                "-only-testing:SurroundUITests/MessagesNavigationUITests",
                "-skip-testing:SurroundUITests/MessagesNavigationUITests/testOther",
                "-test-timeouts-enabled", "YES", "-resultBundlePath", self.bundle]

    def run_supervisor(self, scenario, **options):
        (self.root / "scenario.json").write_text(json.dumps(scenario))
        return subprocess.run(self.command(**options), env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=60)

    def calls(self, name="calls.jsonl"):
        path = self.root / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def status(self):
        return json.loads((self.diagnostics / "status.json").read_text())

    def crash(self, **changes):
        # xcodebuild leaves a simulator that crashed Shutdown.
        first = {"exit": 65, "summary": CRASH_SUMMARY, "reports": [SIM_RENDER_REPORT],
                 "simulatorStateAfter": "Shutdown",
                 "console": ["Restarting after unexpected exit, crash, or test timeout; summary will include totals."]}
        first.update(changes)
        return first

    def test_passing_part_leaves_no_diagnostics(self):
        result = self.run_supervisor({"first": {"exit": 0, "summary": PASSED_SUMMARY}})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"Test Suite 'Selected tests' started", result.stdout)
        self.assertFalse(self.diagnostics.exists())
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(list((self.root / "TestResults").glob(".console-*")), [])

    def test_held_stdout_is_drained_for_a_bounded_time_and_its_holder_killed(self):
        started = time.monotonic()
        result = self.run_supervisor({"first": {"exit": 0, "summary": PASSED_SUMMARY, "inheritStdout": True}})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertLess(time.monotonic() - started, 15)
        self.assertFalse(self.diagnostics.exists())
        pid = int((self.root / "sleeper.pid").read_text())
        for _ in range(50):
            if not alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(alive(pid))

    def test_simulator_crash_reruns_only_the_crashed_test_and_recovers(self):
        old = self.root / "reports" / "Surround-2026-10-24-000000.ips"
        old.write_text(json.dumps({"app_name": "Surround"}) + "\n")
        os.utime(old, (time.time() - 3600, time.time() - 3600))
        result = self.run_supervisor({"first": self.crash(coreLog=RECOVERY),
                                      "rerun": {"exit": 0, "summary": PASSED_SUMMARY}})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"::warning title=Simulator crash recovered::SimRenderServer crashed (EXC_BREAKPOINT "
                      b"SIGTRAP, BUG IN LIBDISPATCH: ulock_wake() failed", result.stdout)
        first, rerun = self.calls()
        self.assertIn("-skip-testing:SurroundUITests/MessagesNavigationUITests/testOther", first)
        self.assertEqual([value for value in rerun if "-testing" in value], ["-only-testing:" + SELECTOR])
        self.assertEqual(rerun[-2:], ["-resultBundlePath", self.bundle[:-len(".xcresult")] + "-Rerun.xcresult"])
        xcrun = self.calls("xcrun.jsonl")
        self.assertLess(xcrun.index(["simctl", "boot", UDID]), xcrun.index(["simctl", "bootstatus", UDID]))
        status = self.status()
        self.assertTrue(status["rerun"]["boot"]["finished"])
        self.assertEqual(status["rerun"]["boot"]["states"], ["Shutdown", "Booted"])
        self.assertEqual(status["rerun"]["causes"], ["crash"])
        self.assertEqual(status["exitCode"], 0)
        self.assertEqual(status["rerun"]["tests"], [SELECTOR])
        self.assertTrue(status["coreSimulatorRecovery"])
        self.assertEqual([report["process"] for report in status["crashReports"]], ["SimRenderServer"])
        self.assertEqual(status["attempts"][0]["consoleMarkers"]["runnerRestarts"], 1)
        self.assertIn(b"Restarting after unexpected exit", (self.diagnostics / "console.log").read_bytes())
        self.assertTrue((self.diagnostics / "rerun-console.log").exists())
        self.assertTrue((self.diagnostics / "DiagnosticReports" / SIM_RENDER_REPORT["name"]).exists())
        self.assertEqual((self.diagnostics / "CoreSimulator.log").read_text(), RECOVERY)

    def test_failed_or_empty_reruns_do_not_recover(self):
        for name, rerun, code in (("failed", {"exit": 65, "summary": CRASH_SUMMARY}, 65),
                                  ("ran no test", {"exit": 0, "summary": EMPTY_SUMMARY}, 65),
                                  ("no bundle", {"exit": 0}, 65)):
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                result = self.run_supervisor({"first": self.crash(), "rerun": rerun})
                self.assertEqual(result.returncode, code, result.stdout)
                self.assertIn(b"::error title=Simulator crash::The rerun of", result.stdout)
                self.assertNotIn(b"recovered", result.stdout)
                self.assertEqual(len(self.calls()), 2)

    def test_gate_failures_keep_the_first_exit_status_without_rerun(self):
        scenarios = {
            "assertion": self.crash(summary=ASSERTION_SUMMARY),
            "no evidence": self.crash(reports=[]),
            "app crash": self.crash(reports=[SIM_RENDER_REPORT, APP_REPORT]),
            "time allowance": self.crash(console=["Test exceeded execution time allowance of 15 minutes"]),
            "no bundle": {"exit": 65, "reports": [SIM_RENDER_REPORT]},
        }
        for name, scenario in scenarios.items():
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                result = self.run_supervisor({"first": scenario})
                self.assertEqual(result.returncode, 65, result.stdout)
                self.assertEqual(len(self.calls()), 1)
                self.assertIn(b"[SurroundCI] No rerun:", result.stdout)
                status = self.status()
                self.assertIsNone(status["rerun"]["tests"])
                self.assertTrue(status["rerun"]["reasonNotRerun"])
                self.assertTrue((self.diagnostics / "console.log").exists())

    def test_too_little_time_or_no_boot_prevents_rerun(self):
        result = self.run_supervisor({"first": self.crash()}, min_rerun=3600)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn("remain", self.status()["rerun"]["reasonNotRerun"])
        self.tearDown()
        self.setUp()
        self.env["FAKE_BOOT_EXIT"] = "1"
        result = self.run_supervisor({"first": self.crash()})
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn(b"did not boot again", result.stdout)

    def test_deadline_interrupts_the_whole_group_once_and_reports_124(self):
        started = time.monotonic()
        result = self.run_supervisor({"first": {"exit": 0, "sleep": 30, "interruptExit": 65, "groupWorker": True,
                                                "summary": CRASH_SUMMARY, "reports": [SIM_RENDER_REPORT]}},
                                     deadline=3)
        self.assertEqual(result.returncode, 124, result.stdout)
        self.assertLess(time.monotonic() - started, 15)
        self.assertIn(b"::error title=UI-test part deadline::", result.stdout)
        self.assertEqual(self.worker_marker.read_text(), "interrupted")
        attempt = self.status()["attempts"][0]
        self.assertTrue(attempt["stoppedAtDeadline"])
        self.assertEqual(attempt["signalsSent"], ["SIGINT"])
        self.assertEqual(attempt["exitCode"], 65)
        self.assertIn("deadline", self.status()["rerun"]["reasonNotRerun"])
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual((self.diagnostics / "deadline.png").read_bytes(), b"fake screenshot")

    def test_deadline_escalates_to_sigkill_when_signals_are_ignored(self):
        result = self.run_supervisor({"first": {"exit": 0, "sleep": 30, "ignore": ["INT", "TERM"]}},
                                     deadline=3, interrupt_grace=0.5)
        self.assertEqual(result.returncode, 124, result.stdout)
        attempt = self.status()["attempts"][0]
        self.assertEqual(attempt["signalsSent"], ["SIGINT", "SIGTERM", "SIGKILL"])
        self.assertEqual(attempt["exitCode"], 128 + signal.SIGKILL)

    def test_deadline_also_stops_the_rerun(self):
        result = self.run_supervisor({"first": self.crash(),
                                      "rerun": {"exit": 0, "sleep": 30, "interruptExit": 65,
                                                "summary": CRASH_SUMMARY}}, deadline=4)
        self.assertEqual(result.returncode, 124, result.stdout)
        self.assertIn(b"The deadline stopped the rerun", result.stdout)
        rerun = self.status()["attempts"][1]
        self.assertTrue(rerun["stoppedAtDeadline"])
        self.assertEqual(rerun["signalsSent"], ["SIGINT"])
        self.assertTrue((self.diagnostics / "rerun-deadline.png").exists())

    def test_outside_signals_interrupt_the_group_and_prevent_rerun(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal.Signals(signum).name):
                self.tearDown()
                self.setUp()
                (self.root / "scenario.json").write_text(json.dumps(
                    {"first": {"exit": 0, "sleep": 30, "interruptExit": 65, "groupWorker": True,
                               "summary": CRASH_SUMMARY, "reports": [SIM_RENDER_REPORT]}}))
                process = subprocess.Popen(self.command(), env=self.env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 20
                    while not self.ready.exists() and time.monotonic() < deadline:
                        time.sleep(0.05)
                    process.send_signal(signum)
                    output, _ = process.communicate(timeout=30)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                self.assertEqual(process.returncode, 128 + signum, output)
                self.assertEqual(self.worker_marker.read_text(), "interrupted")
                status = self.status()
                self.assertEqual(status["attempts"][0]["signalsSent"], ["SIGINT"])
                self.assertEqual(status["attempts"][0]["exitCode"], 65)
                self.assertIn("interrupted", status["rerun"]["reasonNotRerun"])
                self.assertEqual(len(self.calls()), 1)

    def wait_for(self, path, seconds=20):
        deadline = time.monotonic() + seconds
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(path.exists(), path)

    def start_supervisor(self, scenario, **options):
        (self.root / "scenario.json").write_text(json.dumps(scenario))
        return subprocess.Popen(self.command(**options), env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)

    def finish_supervisor(self, process):
        try:
            return process.communicate(timeout=30)[0]
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_group_members_that_ignore_sigint_do_not_outlive_a_stop(self):
        result = self.run_supervisor({"first": {"exit": 0, "sleep": 30, "interruptExit": 65,
                                                "stubbornWorker": True, "summary": CRASH_SUMMARY}}, deadline=3)
        self.assertEqual(result.returncode, 124, result.stdout)
        pid = int((self.root / "sleeper.pid").read_text())
        for _ in range(50):
            if not alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(alive(pid))

    def test_a_second_outside_signal_escalates_without_waiting_for_grace(self):
        process = self.start_supervisor({"first": {"exit": 0, "sleep": 30, "interruptExit": 65,
                                                   "ignore": ["INT"], "summary": CRASH_SUMMARY}},
                                        interrupt_grace=60)
        started = time.monotonic()
        self.wait_for(self.ready)
        process.send_signal(signal.SIGINT)
        time.sleep(0.5)
        process.send_signal(signal.SIGINT)
        output = self.finish_supervisor(process)
        self.assertLess(time.monotonic() - started, 30)
        self.assertEqual(process.returncode, 128 + signal.SIGINT, output)
        attempt = self.status()["attempts"][0]
        self.assertEqual(attempt["signalsSent"], ["SIGINT", "SIGTERM"])
        self.assertEqual(attempt["exitCode"], 78)  # The fake's SIGTERM exit status.

    def test_an_outside_signal_during_the_rerun_wins(self):
        process = self.start_supervisor({"first": self.crash(),
                                         "rerun": {"exit": 0, "sleep": 30, "interruptExit": 65,
                                                   "summary": PASSED_SUMMARY}})
        self.wait_for(Path(str(self.ready) + ".rerun"))
        process.send_signal(signal.SIGTERM)
        output = self.finish_supervisor(process)
        self.assertEqual(process.returncode, 128 + signal.SIGTERM, output)
        self.assertNotIn(b"recovered", output)
        status = self.status()
        self.assertEqual(status["attempts"][1]["signalsSent"], ["SIGINT"])
        self.assertIn("interrupted", status["rerun"]["reasonNotRerun"])
        self.assertIn("crashReports", status["rerun"])

    def test_a_boot_slower_than_the_time_left_is_cut_short(self):
        self.env["FAKE_BOOT_SECONDS"] = "20"
        started = time.monotonic()
        result = self.run_supervisor({"first": self.crash()}, deadline=100, min_rerun=95)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertLess(time.monotonic() - started, 15)
        self.assertIn(b"did not boot again", result.stdout)
        self.assertEqual(len(self.calls()), 1)

    def test_the_time_minimum_is_checked_again_after_a_slow_gate(self):
        # Each slow listing costs 5 s: one before the decision, then two in the gate.
        self.env["FAKE_LIST_SECONDS"] = "5"
        result = self.run_supervisor({"first": self.crash()}, deadline=100, min_rerun=90)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(b"remained after the simulator booted, and the rerun needs 90 s", result.stdout)
        self.assertTrue(self.status()["rerun"]["boot"]["booted"])
        self.assertEqual(len(self.calls()), 1)

    def test_a_query_timeout_rerun_rechecks_its_measured_time_after_the_gate(self):
        # 100 s of overhead plus the 20-s test: one 8-s listing fits before the decision, a second does not.
        self.env["FAKE_LIST_SECONDS"] = "8"
        console = QUERY_TIMEOUT_CONSOLE.replace("129.486 seconds", "20.000 seconds")
        result = self.run_supervisor({"first": self.query_timeout(console=[console])}, deadline=132)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(b"remained after the simulator booted, and the rerun needs 120 s", result.stdout)
        self.assertEqual(self.status()["rerun"]["boot"]["states"], ["Booted"])
        self.assertEqual(len(self.calls()), 1)

    def test_an_outside_signal_ends_the_boot_gate_early(self):
        for name, state, bootstatus_seconds in (("still Booting", "Booting", "0"),
                                                 ("waiting for bootstatus", "Shutdown", "60")):
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                self.env["FAKE_BOOTSTATUS_SECONDS"] = bootstatus_seconds
                process = self.start_supervisor({"first": self.crash(simulatorStateAfter=state)})
                self.wait_for(self.diagnostics / "boot.log")
                if state == "Shutdown":
                    deadline = time.monotonic() + 20
                    while ["simctl", "bootstatus", UDID] not in self.calls("xcrun.jsonl") \
                            and time.monotonic() < deadline:
                        time.sleep(0.05)
                    self.assertIn(["simctl", "bootstatus", UDID], self.calls("xcrun.jsonl"))
                started = time.monotonic()
                process.send_signal(signal.SIGTERM)
                output = self.finish_supervisor(process)
                self.assertLess(time.monotonic() - started, 10)
                self.assertEqual(process.returncode, 128 + signal.SIGTERM, output)
                status = self.status()
                self.assertFalse(status["rerun"]["boot"]["finished"])
                self.assertIn("interrupted", status["rerun"]["reasonNotRerun"])
                if state == "Shutdown":
                    self.assertEqual(status["rerun"]["boot"]["bootStatus"]["error"], "interrupted")
                self.assertEqual(len(self.calls()), 1)

    def test_a_simulator_still_shutting_down_is_booted_once_it_stops(self):
        result = self.run_supervisor({"first": self.crash(simulatorStateAfter="Shutting Down,Shutting Down,"
                                                                              "Shutting Down,Shutdown"),
                                      "rerun": {"exit": 0, "summary": PASSED_SUMMARY}})
        self.assertEqual(result.returncode, 0, result.stdout)
        boot = self.status()["rerun"]["boot"]
        self.assertEqual(boot["states"], ["Shutting Down", "Shutdown", "Booted"])
        self.assertEqual(boot["boot"]["exitCode"], 0)
        self.assertEqual([call for call in self.calls("xcrun.jsonl") if call[:2] == ["simctl", "boot"]],
                         [["simctl", "boot", UDID]])

    def test_a_simulator_that_never_finishes_booting_stops_the_gate_at_its_limit(self):
        # Reading Booted is not enough; the rerun waits for bootstatus, within its spare time.
        self.env["FAKE_BOOTSTATUS_SECONDS"] = "30"
        started = time.monotonic()
        result = self.run_supervisor({"first": self.crash()}, deadline=100, min_rerun=95)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertLess(time.monotonic() - started, 15)
        self.assertIn(b"read Booted, but simctl bootstatus did not report the boot finished within 5 s, "
                      b"all the time the rerun could spare", result.stdout)
        self.assertEqual(len(self.calls()), 1)
        boot_log = (self.diagnostics / "boot.log").read_text()
        self.assertIn("Shutdown", boot_log)
        self.assertIn("Booted", boot_log)
        self.assertIn("Waiting on System App", boot_log)
        self.tearDown()
        self.setUp()
        self.env["FAKE_BOOTSTATUS_EXIT"] = "1"
        result = self.run_supervisor({"first": self.crash()})
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(b"read Booted, but simctl bootstatus exited 1", result.stdout)
        self.assertEqual(len(self.calls()), 1)

    def test_a_boot_that_another_boot_raced_keeps_waiting_for_booted(self):
        # simctl boot exits 149 when the device left Shutdown meanwhile; that is no reason to give up.
        self.env.update(FAKE_BOOT_EXIT="149", FAKE_BOOT_STATE_AFTER="Booting,Booted")
        result = self.run_supervisor({"first": self.crash(), "rerun": {"exit": 0, "summary": PASSED_SUMMARY}})
        self.assertEqual(result.returncode, 0, result.stdout)
        boot = self.status()["rerun"]["boot"]
        self.assertEqual(boot["boot"]["exitCode"], 149)
        self.assertEqual(boot["states"], ["Shutdown", "Booting", "Booted"])
        self.assertTrue(boot["finished"])

    def test_the_boot_gate_stops_at_its_cap_when_the_part_has_time_to_spare(self):
        # In process, so the three-minute cap can be shortened.
        self.env["FAKE_BOOTSTATUS_SECONDS"] = "60"
        (self.root / "scenario.json").write_text(json.dumps({"first": self.crash()}))
        output = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
        started = time.monotonic()
        with mock.patch.dict(os.environ, self.env, clear=True), \
                mock.patch.object(supervise, "BOOT_LIMIT_SECONDS", 3), \
                mock.patch.object(sys, "argv", ["supervise"] + self.command()[2:]), \
                mock.patch.object(sys, "stdout", output), mock.patch.object(sys, "stderr", io.StringIO()):
            code = supervise.main()
            output.flush()
        self.assertEqual(code, 65)
        self.assertLess(time.monotonic() - started, 20)
        text = output.buffer.getvalue()
        self.assertIn(b"did not report the boot finished within 3 s.", text)
        self.assertNotIn(b"all the time the rerun could spare", text)
        self.assertEqual(len(self.calls()), 1)

    def test_a_simulator_that_never_reads_booted_stops_the_gate_at_its_limit(self):
        started = time.monotonic()
        result = self.run_supervisor({"first": self.crash(simulatorStateAfter="Booting")},
                                     deadline=100, min_rerun=95)
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertLess(time.monotonic() - started, 15)
        self.assertIn(b"did not boot again: it was still Booting after 5 s, all the time", result.stdout)
        self.assertNotIn(["simctl", "boot", UDID], self.calls("xcrun.jsonl"))
        self.assertEqual(len(self.calls()), 1)

    def query_timeout(self, **changes):
        first = {"exit": 65, "summary": QUERY_TIMEOUT_SUMMARY, "console": [QUERY_TIMEOUT_CONSOLE]}
        first.update(changes)
        return first

    def test_a_query_timeout_reruns_on_the_booted_simulator_and_recovers(self):
        result = self.run_supervisor({"first": self.query_timeout(),
                                      "rerun": {"exit": 0, "summary": PASSED_SUMMARY}})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"::warning title=UI query timeout recovered::A UI query timed out during " +
                      QUERY_SELECTOR.encode() + b"; it passed on a rerun.", result.stdout)
        first, rerun = self.calls()
        self.assertEqual([value for value in rerun if "-testing" in value], ["-only-testing:" + QUERY_SELECTOR])
        self.assertNotIn(["simctl", "boot", UDID], self.calls("xcrun.jsonl"))
        self.assertIn(["simctl", "bootstatus", UDID], self.calls("xcrun.jsonl"))
        status = self.status()
        self.assertEqual(status["exitCode"], 0)
        self.assertEqual(status["rerun"]["causes"], ["queryTimeout"])
        self.assertEqual(status["rerun"]["neededSeconds"], 229)
        self.assertEqual(status["rerun"]["boot"]["states"], ["Booted"])
        self.assertIsNone(status["crashSummary"])
        self.assertEqual(status["attempts"][0]["failedTestSeconds"], {QUERY_SELECTOR: 129.486})

    def test_a_query_timeout_rerun_needs_its_measured_time_and_must_pass(self):
        result = self.run_supervisor({"first": self.query_timeout()}, deadline=220)
        self.assertEqual(result.returncode, 65, result.stdout)
        # The remaining time counts from the supervisor's start, so a busy machine can shave a second off.
        self.assertRegex(result.stdout, rb"No rerun: only 2[0-2]\d s remain before the deadline, and the rerun needs 229 s")
        self.assertEqual(len(self.calls()), 1)
        self.tearDown()
        self.setUp()
        result = self.run_supervisor({"first": self.query_timeout(),
                                      "rerun": {"exit": 65, "summary": QUERY_TIMEOUT_SUMMARY}})
        self.assertEqual(result.returncode, 65, result.stdout)
        self.assertIn(b"::error title=UI query timeout::The rerun of " + QUERY_SELECTOR.encode() +
                      b" after a UI query timeout did not pass", result.stdout)
        self.assertEqual(len(self.calls()), 2)

    def test_cli_rejects_reused_diagnostics_and_unbounded_commands(self):
        self.diagnostics.mkdir()
        result = subprocess.run(self.command(), env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=30)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"already exists", result.stdout)
        self.diagnostics.rmdir()
        for command in (self.command()[:-2], [part if part != UDID else "booted" for part in self.command()]):
            result = subprocess.run(command, env=self.env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=30)
            self.assertEqual(result.returncode, 2, result.stdout)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
