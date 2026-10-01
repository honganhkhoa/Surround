#!/usr/bin/env python3
"""Native-resize collector tests use fake tools only, never a simulator or sudo."""

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

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parent / "diagnose-ipad-animation-stalls.py"
if not SCRIPT.is_file():  # Repository layout keeps these tests in ci-tools/tests/.
    SCRIPT = Path(__file__).resolve().parents[1] / "diagnose-ipad-animation-stalls.py"
spec = importlib.util.spec_from_file_location("native_capture_diagnostics", SCRIPT)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)
UDID = "11111111-2222-3333-4444-555555555555"
START = "Test Case '-[SurroundUITests.GameContinuityUITests testMovePreviewKeepsAnExitAcrossLayouts]' started."
OTHER_START = START.replace("testMovePreviewKeepsAnExitAcrossLayouts", "testSomeOtherJourney")
FINISHED = START.replace("started.", "passed (2.000 seconds).")
BEGIN = "[SurroundNativeResizeCapture] BEGIN cycle=1"
ACTION = "[SurroundNativeResizeCapture] ACTION cycle=1"
RESTORED = "[SurroundNativeResizeCapture] RESTORED cycle=1"


class NativeDetectorTests(unittest.TestCase):
    def test_exact_test_and_first_cycle_are_required(self):
        detector = diagnostics.NativeResizeDetector()
        self.assertIsNone(detector.feed(BEGIN, 0))
        detector.feed(OTHER_START, 1)
        self.assertIsNone(detector.feed(BEGIN, 2))
        detector.feed(START, 3)
        self.assertIsNone(detector.feed(BEGIN.replace("cycle=1", "cycle=2"), 4))
        self.assertIsNotNone(detector.feed(BEGIN, 5))
        self.assertIsNone(detector.feed(BEGIN, 6))

    def test_markers_and_completion_are_ordered_and_one_shot(self):
        detector = diagnostics.NativeResizeDetector()
        detector.feed(START, 0)
        detector.feed(ACTION, 1)
        detector.feed(RESTORED, 2)
        self.assertFalse(detector.action.is_set())
        self.assertFalse(detector.restored.is_set())
        detector.feed(BEGIN, 3)
        detector.feed(ACTION, 4)
        self.assertTrue(detector.action.is_set())
        detector.feed(RESTORED, 5)
        self.assertTrue(detector.restored.is_set())
        detector.feed(FINISHED, 6)
        self.assertTrue(detector.finished.is_set())
        detector.feed(START, 7)
        self.assertIsNone(detector.feed(BEGIN, 8))


FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, sys, time
root = pathlib.Path(os.environ["FAKE_ROOT"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps([name] + args) + "\n")
if name == "xcrun" and "/bin/sh" in args:
    (root / "stream.pid").write_text(str(os.getpid()))
    def end_stream(signum, frame):
        (root / "stream-stopped").write_text(str(signum))
        sys.exit(0)
    signal.signal(signal.SIGTERM, end_stream)
    print("SurroundAnimationCollectorPID=" + str(os.getpid()), flush=True)
    while True: time.sleep(.02)
elif name == "xcrun" and args[-2:] == ["launchctl", "list"]:
    print("1110 0 UIKitApplication:com.honganhkhoa.Surround[abc][rb-legacy]")
    print("2220 0 UIKitApplication:com.honganhkhoa.SurroundUITests.xctrunner[def]")
    print("3330 0 UIKitApplication:com.honganhkhoa.SurroundWidgets[widget]")
    if os.environ.get("FAKE_AMBIGUOUS_APP"):
        print("4440 0 UIKitApplication:com.honganhkhoa.Surround[duplicate]")
elif name == "xcrun" and "recordVideo" in args:
    if os.environ.get("FAKE_VIDEO_FAIL"):
        print("synthetic video failure", flush=True)
        sys.exit(19)
    destination = pathlib.Path(args[-1])
    (root / "recorder.pid").write_text(str(os.getpid()))
    print("Recording started", flush=True)
    def end_video(signum, frame):
        with (root / "recorder-signals.jsonl").open("a") as stream:
            stream.write(json.dumps(signum) + "\n")
        if os.environ.get("FAKE_VIDEO_IGNORE_SIGINT"):
            if signum == signal.SIGINT:
                return
            (root / "recorder-stopped").write_text(str(signum))
            sys.exit(0)
        (root / "recorder-stopped").write_text(str(signum))
        destination.write_bytes(b"finalized synthetic video")
        sys.exit(0)
    signal.signal(signal.SIGINT, end_video)
    signal.signal(signal.SIGTERM, end_video)
    while True: time.sleep(.02)
elif name == "sudo":
    if "/bin/kill" in args:
        if os.environ.get("FAKE_CLEANUP_FAIL"):
            print("synthetic noninteractive cleanup failure", flush=True)
            sys.exit(17)
        os.kill(int(args[-1]), signal.SIGTERM)
        sys.exit(0)
    (root / "stack-started").write_text(str(time.monotonic()))
    (root / "stack.pid").write_text(str(os.getpid()))
    if os.environ.get("FAKE_STACK_HANG"):
        while True: time.sleep(.02)
    time.sleep(.2)
    if os.environ.get("FAKE_STACK_FAIL"):
        print("synthetic noninteractive sudo failure", flush=True)
        (root / "stack-done").write_text(str(time.monotonic()))
        sys.exit(17)
    for option in ("-o", "-file"):
        if option in args:
            pathlib.Path(args[args.index(option) + 1]).write_text("synthetic raw spindump")
    (root / "stack-done").write_text(str(time.monotonic()))
elif name == "ps":
    sys.exit(1)
elif name == "xcrun" and "screenshot" in args:
    pathlib.Path(args[-1]).write_bytes(b"synthetic screenshot")
elif name == "sample":
    pathlib.Path(args[args.index("-file") + 1]).write_text("synthetic sample")
else:
    print("unexpected fake tool invocation", [name] + args, flush=True)
    sys.exit(99)
'''


class NativeWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / "result"
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        for name in ("xcrun", "sudo", "sample", "ps"):
            path = fake_bin / name
            path.write_text(FAKE_TOOL)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"],
                                FAKE_ROOT=str(self.root), PYTHONDONTWRITEBYTECODE="1")

    def tearDown(self):
        # A deliberately failed fake sudo cleanup leaves our own fake collector
        # alive; clean up that known test process after observing the uncertainty.
        pid_file = self.root / "stack.pid"
        if os.environ.get("FAKE_STACK_HANG") or self.environment.get("FAKE_STACK_HANG"):
            if pid_file.exists():
                try:
                    os.killpg(int(pid_file.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
        self.temporary.cleanup()

    def command(self, source, enabled=True, extra=()):
        return [sys.executable, str(SCRIPT), "--simulator", UDID, "--output", str(self.output),
                "--log-seconds", "5", "--capture-timeout", "1",
                *(["--native-resize-capture", "--native-capture-seconds", "6",
                   "--native-stack-seconds", "1"] if enabled else []), *extra,
                "--", sys.executable, "-u", "-c", source]

    def invoke(self, source, enabled=True, extra=()):
        result = subprocess.run(self.command(source, enabled, extra), env=self.environment,
                                capture_output=True, timeout=8)
        status = json.loads((self.output / "status.json").read_text())
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertTrue((self.root / "stream-stopped").exists())
        self.assertEqual((self.output / "console.log").read_bytes(), result.stdout)
        for call in calls:
            if call[0] == "xcrun":
                self.assertIn(UDID, call)
                self.assertNotIn("booted", call)
        return result, status, calls

    def capture_source(self, exit_code=0, restored=True, finish=True, delay=.05):
        return (
            "import pathlib,time,sys\n"
            "print(%r)\nprint(%r)\n"
            "deadline=time.monotonic()+2\n"
            "while not pathlib.Path(%r).exists() and time.monotonic()<deadline: time.sleep(.01)\n"
            "print(%r)\n"
            "deadline=time.monotonic()+2\n"
            "while not pathlib.Path(%r).exists() and time.monotonic()<deadline: time.sleep(.01)\n"
            "pathlib.Path(%r).write_text(str(time.monotonic()))\nprint('test continued')\n"
            "while not pathlib.Path(%r).exists() and time.monotonic()<deadline: time.sleep(.01)\n"
            "%s\n%s\ntime.sleep(%r)\nsys.exit(%d)\n"
        ) % (START, BEGIN, str(self.root / "recorder.pid"), ACTION,
             str(self.root / "stack-started"), str(self.root / "test-continued"),
             str(self.root / "stack-done"), "print(%r)" % RESTORED if restored else "pass",
             "print(%r)" % FINISHED if finish else "pass", delay, exit_code)

    def assert_owned_video_finished(self, calls):
        self.assertEqual(sum("recordVideo" in call for call in calls), 1)
        self.assertEqual(int((self.root / "recorder-stopped").read_text()), signal.SIGINT)
        recording = next(call for call in calls if "recordVideo" in call)
        self.assertEqual(Path(recording[-1]).read_bytes(), b"finalized synthetic video")

    def test_opt_in_required_even_with_exact_marker(self):
        result, status, calls = self.invoke("print(%r); print(%r); print(%r)" % (START, BEGIN, ACTION), enabled=False)
        self.assertEqual(result.returncode, 0)
        self.assertIsNone(status.get("nativeResizeCapture"))
        self.assertFalse(any("recordVideo" in call or call[0] == "sudo" for call in calls))

    def test_unrelated_test_cannot_start_native_capture(self):
        result, status, calls = self.invoke("print(%r); print(%r); print(%r)" % (OTHER_START, BEGIN, ACTION))
        self.assertEqual(result.returncode, 0)
        self.assertIsNone(status.get("nativeResizeCapture"))
        self.assertFalse(any("recordVideo" in call or call[0] == "sudo" for call in calls))

    def test_success_finalizes_video_and_targets_raw_app_stack_without_pausing_test(self):
        source = self.capture_source().replace("print(%r)\n" % ACTION,
                                               "print(%r)\nprint(%r)\n" % (BEGIN, ACTION))
        result, status, calls = self.invoke(source)
        self.assertEqual(result.returncode, 0)
        self.assertIsNotNone(status["nativeResizeCapture"])
        self.assert_owned_video_finished(calls)
        [stack] = [call for call in calls if call[0] == "sudo"]
        self.assertEqual(stack[1], "-n")
        self.assertEqual(Path(stack[2]).name, "spindump")
        self.assertIn("1110", stack)
        self.assertNotIn("2220", stack)
        self.assertNotIn("3330", stack)
        for option in ("-noText", "-noSymbolicate", "-onlyTarget", "-timelimit"):
            self.assertIn(option, stack)
        self.assertGreaterEqual(int(stack[stack.index("-timelimit") + 1]), 2)
        self.assertLessEqual(int(stack[stack.index("-timelimit") + 1]), 12)
        self.assertLess(float((self.root / "test-continued").read_text()),
                        float((self.root / "stack-done").read_text()))
        self.assertIn(b"test continued", result.stdout)

    def test_test_failure_finalizes_video_and_preserves_exit_status(self):
        result, status, calls = self.invoke(self.capture_source(exit_code=65, restored=False, finish=False))
        self.assertEqual((result.returncode, status["commandExitCode"]), (65, 65))
        self.assert_owned_video_finished(calls)

    def test_deadline_finalizes_video_while_test_continues(self):
        source = "import time; print(%r); print(%r); time.sleep(1.3); print(\"test continued\")" % (START, BEGIN)
        result, _, calls = self.invoke(source, extra=["--native-capture-seconds", "1"])
        self.assertEqual(result.returncode, 0)
        self.assert_owned_video_finished(calls)

    def test_deadline_recorder_cleanup_keeps_test_running_and_reports_missing_video(self):
        self.environment["FAKE_VIDEO_IGNORE_SIGINT"] = "1"
        source = "import time; print(%r); print(%r); time.sleep(1.3); print('test continued')" % (START, BEGIN)
        started = time.monotonic()
        result, status, calls = self.invoke(source, extra=["--native-capture-seconds", "1"])
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"test continued", result.stdout)
        self.assertEqual(sum("recordVideo" in call for call in calls), 1)
        signals = [json.loads(line) for line in (self.root / "recorder-signals.jsonl").read_text().splitlines()]
        self.assertEqual(signals, [signal.SIGINT, signal.SIGTERM])
        video = status["nativeResizeCapture"]["video"]
        self.assertTrue(video["cleanup"]["stopped"])
        self.assertFalse(video["artifactExists"])
        self.assertIn("Recorder did not finalize", video["error"])

    def test_privileged_sampler_timeout_stops_exact_wrapper_and_reports_sampler_uncertainty(self):
        self.environment["FAKE_STACK_HANG"] = "1"
        result, status, calls = self.invoke(self.capture_source(exit_code=65, restored=False, finish=False))
        self.assertEqual((result.returncode, status["commandExitCode"]), (65, 65))
        self.assert_owned_video_finished(calls)
        raw = status["nativeResizeCapture"]["tools"]["rawStack"]
        self.assertEqual(raw["error"], "collector timeout")
        self.assertTrue(raw["cleanup"]["wrapperStopped"])
        self.assertFalse(raw["cleanup"]["collectorExitConfirmed"])
        [cleanup] = [call for call in calls if call[0] == "sudo" and "/bin/kill" in call]
        self.assertEqual(cleanup, ["sudo", "-n", "/bin/kill", "-TERM", (self.root / "stack.pid").read_text()])
        self.assertNotIn("1110", cleanup)
        self.assertNotIn("2220", cleanup)

    def test_failed_privileged_cleanup_reports_uncertainty_without_masking_test_result(self):
        self.environment.update(FAKE_STACK_HANG="1", FAKE_CLEANUP_FAIL="1")
        result, status, calls = self.invoke(self.capture_source(exit_code=65, restored=False, finish=False))
        self.assertEqual((result.returncode, status["commandExitCode"]), (65, 65))
        self.assert_owned_video_finished(calls)
        raw = status["nativeResizeCapture"]["tools"]["rawStack"]
        self.assertEqual(raw["error"], "collector timeout")
        self.assertIsNone(raw["exitCode"])
        self.assertFalse(raw["cleanup"]["wrapperStopped"])
        self.assertFalse(raw["cleanup"]["collectorExitConfirmed"])
        self.assertEqual(raw["cleanup"]["exitCode"], 17)
        self.assertIn("error", raw["cleanup"])
        [cleanup] = [call for call in calls if call[0] == "sudo" and "/bin/kill" in call]
        self.assertEqual(cleanup, ["sudo", "-n", "/bin/kill", "-TERM", (self.root / "stack.pid").read_text()])
        # The failed fake cleanup really left its own collector alive. This is
        # reported rather than interpreted as proof it exited; tearDown owns it.
        os.kill(int((self.root / "stack.pid").read_text()), 0)

    def test_noninteractive_stack_failure_does_not_mask_test_failure(self):
        self.environment["FAKE_STACK_FAIL"] = "1"
        result, status, calls = self.invoke(self.capture_source(exit_code=65, restored=False, finish=False))
        self.assertEqual((result.returncode, status["commandExitCode"]), (65, 65))
        self.assert_owned_video_finished(calls)
        self.assertIn("17", json.dumps(status["nativeResizeCapture"]))

    def test_ambiguous_app_jobs_refuse_raw_stack_and_preserve_test_result(self):
        self.environment["FAKE_AMBIGUOUS_APP"] = "1"
        source = ("import time; print(%r); print(%r); time.sleep(.1); "
                  "print(%r); time.sleep(.2); print(%r)") % (START, BEGIN, ACTION, FINISHED)
        result, status, calls = self.invoke(source)
        self.assertEqual(result.returncode, 0)
        self.assert_owned_video_finished(calls)
        self.assertFalse(any(call[0] == "sudo" for call in calls))
        self.assertIn("Multiple matching app", json.dumps(status["nativeResizeCapture"]))

    def test_recorder_failure_is_nonfatal_and_preserves_test_result(self):
        self.environment["FAKE_VIDEO_FAIL"] = "1"
        source = ("import time,sys; print(%r); print(%r); time.sleep(.1); "
                  "print(%r); time.sleep(.3); sys.exit(65)") % (START, BEGIN, ACTION)
        result, status, _ = self.invoke(source)
        self.assertEqual((result.returncode, status["commandExitCode"]), (65, 65))
        self.assertIsNotNone(status["nativeResizeCapture"])
        self.assertFalse((self.root / "recorder-stopped").exists())
        self.assertIn("No compositor video artifact", json.dumps(status["nativeResizeCapture"]))

    def test_sigterm_finalizes_only_owned_video_and_preserves_signal_status(self):
        source = "import time; print(%r); print(%r); time.sleep(60)" % (START, BEGIN)
        process = subprocess.Popen(self.command(source), env=self.environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (self.root / "recorder.pid").exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue((self.root / "recorder.pid").exists())
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 143)
            calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
            self.assert_owned_video_finished(calls)
            status = json.loads((self.output / "status.json").read_text())
            self.assertEqual(status["signal"], signal.SIGTERM)
            self.assertEqual(status["commandExitCode"], -signal.SIGTERM)
            self.assertFalse(any(call[0] == "sudo" for call in calls))
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_native_bounds_rejected_before_wrapped_command_runs(self):
        for extra in (["--native-capture-seconds", "0"], ["--native-capture-seconds", "21"],
                      ["--native-stack-seconds", "0"], ["--native-stack-seconds", "6"]):
            with self.subTest(extra=extra):
                result = subprocess.run(self.command("print('should never run')", extra=extra),
                                        env=self.environment, capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
