#!/usr/bin/env python3
"""Collector regression tests use fake tools only, never a real simulator."""

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "diagnose-ipad-animation-stalls.py"
spec = importlib.util.spec_from_file_location("animation_stalls", SCRIPT)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)
UDID = "11111111-2222-3333-4444-555555555555"
START = "Test Case '-[SurroundUITests.SurroundUITests testShare]' started."
ARM = "[SurroundAnimationTest] ARM share uptime=1.0"
IDLE = "    t =    20.00s     Wait for com.honganhkhoa.Surround to idle"


class DetectorTests(unittest.TestCase):
    def test_launch_idle_and_unrelated_processes_do_not_arm(self):
        detector = diagnostics.StallDetector(15)
        detector.feed(START, 0)
        detector.feed(IDLE, 1)
        self.assertIsNone(detector.check(60))
        detector.feed(ARM, 61)
        detector.feed("t = 62.00s Wait for com.apple.springboard to idle", 62)
        self.assertIsNone(detector.check(90))

    def test_duplicate_idle_and_app_tracing_do_not_hide_stall(self):
        detector = diagnostics.StallDetector(15)
        for line, now in [(START, 0), (ARM, 1), (IDLE, 2),
                          (IDLE, 9), ("[SurroundAnimation] keyboard did hide", 14)]:
            detector.feed(line, now)
        self.assertEqual(detector.check(17)["reason"], "long-idle-wait")
        self.assertIsNone(detector.feed(diagnostics.WARNING, 62))
        self.assertIsNone(detector.check(120))

    def test_activity_and_test_boundaries_reset_wait_and_arming(self):
        detector = diagnostics.StallDetector(15)
        for line, now in [(START, 0), (ARM, 1), (IDLE, 2),
                          ('t = 4.00s Find the "game.chat" Button', 4)]:
            detector.feed(line, now)
        self.assertIsNone(detector.check(30))
        detector.feed(START.replace("testShare", "testNext"), 31)
        detector.feed(IDLE, 32)
        self.assertIsNone(detector.check(60))
        detector.feed(ARM, 61)
        detector.feed(IDLE, 62)
        detector.feed("Test Case '-[Tests testNext]' passed (4 seconds).", 63)
        self.assertIsNone(detector.check(100))

    def test_share_action_arms_warning_fallback_once(self):
        detector = diagnostics.StallDetector(15)
        detector.feed(START, 0)
        detector.feed('t = 1.00s Tap "game.analyze.share" Button', 1)
        self.assertEqual(detector.feed(diagnostics.WARNING, 2)["reason"], "missing-animation-completion")
        self.assertIsNone(detector.feed(diagnostics.WARNING, 3))

    def test_warning_captures_without_share_but_long_idle_still_needs_arming(self):
        detector = diagnostics.StallDetector(15)
        self.assertIsNone(detector.feed(diagnostics.WARNING, 0))
        detector.feed(START, 1)
        detector.feed(IDLE, 2)
        self.assertIsNone(detector.check(30))
        trigger = detector.feed(
            "    t =    62.00s " + diagnostics.WARNING + ", will attempt to continue.", 62)
        self.assertEqual(trigger["reason"], "missing-animation-completion")
        self.assertIsNone(trigger["armSource"])

    def test_process_selection_uses_exact_jobs_and_rejects_ambiguity(self):
        text = ("11 0 UIKitApplication:com.honganhkhoa.Surround[abc][rb-legacy]\n"
                "22 0 UIKitApplication:com.honganhkhoa.SurroundUITests.xctrunner[def]\n"
                "33 0 UIKitApplication:com.honganhkhoa.SurroundWidgets[ghi]\n"
                "44 0 com.honganhkhoa.Surround\n")
        self.assertEqual({k: v["pid"] for k, v in diagnostics.simulator_pids(text).items()},
                         {"app": 11, "runner": 22})
        with self.assertRaisesRegex(ValueError, "Multiple matching app"):
            diagnostics.simulator_pids(text + "55 0 UIKitApplication:com.honganhkhoa.Surround[duplicate]\n")


XCT = "[com.apple.dt.xctest:Default]"


class AnimationIdleSummaryTests(unittest.TestCase):
    def write(self, directory, name, lines):
        path = Path(directory) / name
        path.write_text("\n".join(lines) + "\n")
        return path

    def test_pairs_requests_per_process_and_reports_unanswered_context(self):
        with tempfile.TemporaryDirectory() as directory:
            log = self.write(directory, "simulator.log", [
                "2026-09-13 17:44:20.000 Df Surround[100:1a] " + XCT + " Received request to notify when animations are idle",
                "2026-09-13 17:44:20.200 Df Surround[200:2b] " + XCT + " Received request to notify when animations are idle",
                "2026-09-13 17:44:20.300 Df Surround[100:1a] " + XCT + " Sending animations idle reply with error: (null)",
                "2026-09-13 17:44:26.083 Df Surround[200:2b] [com.apple.UIKit:UIInputLayoutItem] Running state transition with normal animations",
                "2026-09-13 17:44:26.100 Df Surround[200:2b] " + XCT + " Sending animations idle reply with error: (null)",
                "2026-09-13 17:44:26.200 Df Surround[200:2b] [com.apple.TextInputUI:KeyboardTrackingCoordinator] Posted notification willHide with {",
                "2026-09-13 17:44:26.255 Df Surround[200:2b] " + XCT + " Received request to notify when animations are idle",
                "2026-09-13 17:44:26.521 Df Surround[200:2b] [com.apple.UIKit:UIInputLayoutItem] Finished state transition finalState:1",
                "2026-09-13 17:45:26.719 Df Surround[200:2b] " + XCT + " Received request to fetch matches for query",
                "SurroundAnimationCollectorPID=42",
            ])
            console = self.write(directory, "console.log", ["t = 64.00s " + diagnostics.WARNING + ", will attempt to continue."])
            summary = diagnostics.summarize_animation_idle(log, console)
        self.assertEqual((summary["requests"], summary["replies"], summary["repliesWithError"]), (3, 2, 0))
        self.assertEqual(summary["consoleAnimationCompletionWarnings"], 1)
        [stall] = summary["unanswered"]
        self.assertEqual((stall["pid"], stall["requestedAt"]), (200, "2026-09-13 17:44:26.255"))
        self.assertEqual(stall["secondsUntilNextXCTestActivity"], 60.464)
        self.assertEqual(len(stall["precedingInputTransitions"]), 2)
        self.assertIn("willHide", stall["precedingInputTransitions"][-1])

    def test_reply_errors_open_requests_and_missing_logs_do_not_raise(self):
        with tempfile.TemporaryDirectory() as directory:
            log = self.write(directory, "simulator.log", [
                "2026-09-13 17:44:20.000 Df Surround[300:3c] " + XCT + " Sending animations idle reply with error: Error Domain=XCTest Code=1",
                "2026-09-13 17:44:21.000 Df Surround[300:3c] " + XCT + " Received request to notify when animations are idle",
            ])
            summary = diagnostics.summarize_animation_idle(log, Path(directory) / "missing-console.log")
            missing = diagnostics.summarize_animation_idle(
                Path(directory) / "missing.log", Path(directory) / "missing-console.log")
        self.assertEqual((summary["replies"], summary["repliesWithError"]), (1, 1))
        self.assertIsNone(summary["unanswered"][0]["secondsUntilNextXCTestActivity"])
        self.assertIn("consoleError", summary)
        self.assertIn("error", missing)
        self.assertEqual(missing["unanswered"], [])


FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, sys, time
root = pathlib.Path(os.environ["FAKE_ROOT"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as f:
    f.write(json.dumps([name] + args) + "\n")
if name == "xcrun" and "/bin/sh" in args:
    (root / "stream.pid").write_text(str(os.getpid()))
    def end(signum, frame):
        (root / "stream-stopped").write_text(str(signum))
        sys.exit(0)
    signal.signal(signal.SIGTERM, end)
    print("SurroundAnimationCollectorPID=" + str(os.getpid()), flush=True)
    while True:
        time.sleep(0.05)
elif name == "xcrun" and args[-2:] == ["launchctl", "list"]:
    print("1110 0 UIKitApplication:com.honganhkhoa.Surround[abc][rb-legacy]")
    print("2220 0 UIKitApplication:com.honganhkhoa.SurroundUITests.xctrunner[def]")
    print("3330 0 UIKitApplication:com.example.unrelated[ghi]")
elif name == "xcrun" and "screenshot" in args:
    pathlib.Path(args[-1]).write_bytes(b"fake simulator screenshot")
elif name == "sample":
    if os.environ.get("FAKE_SAMPLE_HANG"):
        time.sleep(60)
    if os.environ.get("FAKE_SAMPLE_FAIL"):
        print("synthetic sample permission failure", flush=True)
        (root / ("sample-" + args[0] + "-done")).touch()
        sys.exit(17)
    pathlib.Path(args[args.index("-file") + 1]).write_text("synthetic sample " + args[0])
    (root / ("sample-" + args[0] + "-done")).touch()
elif name == "ps":
    sys.exit(1)
else:
    sys.exit(99)
'''


class WrapperSubprocessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / "result"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("xcrun", "sample", "ps"):
            path = self.bin / name
            path.write_text(FAKE_TOOL)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                FAKE_ROOT=str(self.root), PYTHONDONTWRITEBYTECODE="1")

    def tearDown(self):
        self.temporary.cleanup()

    def command(self, source, extra=()):
        return [sys.executable, str(SCRIPT), "--simulator", UDID, "--output", str(self.output),
                "--stall-seconds", "0.12", "--capture-timeout", "2", "--log-seconds", "5",
                *extra, "--", sys.executable, "-u", "-c", source]

    def invoke(self, source, extra=()):
        result = subprocess.run(self.command(source, extra), env=self.environment,
                                capture_output=True, timeout=8)
        status = json.loads((self.output / "status.json").read_text())
        calls = [json.loads(x) for x in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertTrue((self.root / "stream-stopped").exists())
        for call in calls:
            if call[0] == "xcrun":
                self.assertIn(UDID, call)
                self.assertNotIn("booted", call)
        self.assertEqual((self.output / "console.log").read_bytes(), result.stdout)
        return result, status, calls

    def test_normal_completion_preserves_raw_console_and_nonzero_exit(self):
        source = "import time,sys; print(%r); print(%r); time.sleep(.3); sys.exit(65)" % (START, IDLE)
        result, status, calls = self.invoke(source)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(status["commandExitCode"], 65)
        self.assertIsNone(status["capture"])
        self.assertEqual((status["animationIdle"]["requests"], status["animationIdle"]["unanswered"]), (0, []))
        self.assertFalse(any(c[0] == "sample" for c in calls))

    def test_chunked_lines_long_wait_and_warning_capture_once_without_pausing_command(self):
        source = ("import sys,time; print(%r); sys.stdout.write(%r); sys.stdout.flush(); "
                  "time.sleep(.03); print(%r); print(%r); time.sleep(.18); "
                  "print('[SurroundAnimation] unrelated trace'); time.sleep(.4); print(%r); "
                  "print('command continued'); sys.exit(0)") % (START, ARM[:19], ARM[19:], IDLE, diagnostics.WARNING)
        result, status, calls = self.invoke(source)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(status["trigger"]["reason"], "long-idle-wait")
        self.assertEqual(sorted(c[1] for c in calls if c[0] == "sample"), ["1110", "2220"])
        self.assertEqual(sum("screenshot" in c for c in calls), 1)
        self.assertIn(b"command continued", result.stdout)
        self.assertTrue((self.output / "early-capture/app.sample.txt").exists())

    def test_capture_failure_does_not_mask_test_failure(self):
        self.environment["FAKE_SAMPLE_FAIL"] = "1"
        source = ("import time,sys,pathlib; print(%r); print(%r); print(%r); "
                  "deadline=time.monotonic()+3\n"
                  "while not pathlib.Path(%r).exists() and time.monotonic()<deadline: time.sleep(.02)\n"
                  "time.sleep(.1); sys.exit(65)") % (START, ARM, diagnostics.WARNING, str(self.root / "sample-2220-done"))
        result, status, _ = self.invoke(source)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(status["trigger"]["reason"], "missing-animation-completion")
        self.assertEqual(status["capture"]["tools"]["app"]["exitCode"], 17)
        self.assertIn("error", status["capture"]["tools"]["runner"])

    def test_hanging_collectors_are_bounded_and_do_not_kill_test(self):
        self.environment["FAKE_SAMPLE_HANG"] = "1"
        source = "import time,sys; print(%r); print(%r); print(%r); time.sleep(1.2); print('finished'); sys.exit(0)" % (START, ARM, diagnostics.WARNING)
        result, status, _ = self.invoke(source, ["--capture-timeout", "0.5"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(status["capture"]["tools"]["app"]["error"], "collector timeout")
        self.assertIn(b"finished", result.stdout)

    def test_sigterm_cleans_owned_stream_and_preserves_signal_status(self):
        source = "import time; print(%r); time.sleep(60)" % START
        process = subprocess.Popen(self.command(source), env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (self.root / "stream.pid").exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue((self.root / "stream.pid").exists())
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143)
            self.assertTrue((self.root / "stream-stopped").exists())
            status = json.loads((self.output / "status.json").read_text())
            self.assertEqual(status["signal"], signal.SIGTERM)
            self.assertEqual(status["commandExitCode"], -signal.SIGTERM)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_inherited_stdout_is_drained_for_a_bounded_time(self):
        child_pid = self.root / "inherited-stdout.pid"
        source = ("import subprocess,sys,pathlib,time; "
                  "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                  "pathlib.Path(%r).write_text(str(p.pid)); print('parent exiting'); time.sleep(.2); sys.exit(7)") % str(child_pid)
        try:
            result, status, _ = self.invoke(source)
            self.assertEqual(result.returncode, 7)
            self.assertTrue(any("Console drain stopped" in error for error in status["errors"]))
        finally:
            if child_pid.exists():
                try:
                    os.kill(int(child_pid.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def test_log_collector_exception_keeps_wrapped_exit_code(self):
        args = type("Args", (), {"simulator": UDID, "output": str(self.output), "stall_seconds": 15,
                                  "command": [sys.executable, "-c", "import sys; sys.exit(7)"]})()
        with mock.patch.object(diagnostics, "log_stream", side_effect=RuntimeError("synthetic log crash")):
            self.assertEqual(diagnostics.run(args), 7)
        status = json.loads((self.output / "status.json").read_text())
        self.assertEqual(status["simulatorLog"]["error"], "synthetic log crash")
        self.assertIn("error", status["animationIdle"])


if __name__ == "__main__":
    unittest.main()
