#!/usr/bin/env python3
"""Opt-in, one-shot evidence collection around an unchanged XCTest command.

Usage: diagnose-ipad-animation-stalls.py --simulator UUID --output DIR -- xcodebuild ...
No simulator settings are changed. A captured idle wait is evidence, not a
diagnosis of an application deadlock. Python 3.9+; macOS sample, ps and xcrun.
"""

import argparse
import concurrent.futures
from datetime import datetime
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import threading
import time
import uuid


APP = "com.honganhkhoa.Surround"
RUNNER = APP + "UITests.xctrunner"
ARM_MARKER = "[SurroundAnimationTest] ARM share"
WARNING = "App animations complete notification not received"
EVENT_LOOP_WARNING = "App event loop idle notification not received"
ACTIVITY = re.compile(r"^\s*t\s*=\s*[0-9.]+s\s+(.+)$")
IDLE = "Wait for " + APP + " to idle"
LOG_PREDICATE = (
    '(process == "Surround" OR process == "SurroundUITests-Runner" '
    'OR process == "testmanagerd") AND '
    '(category == "UIAnimationDiagnostics" '
    'OR eventMessage CONTAINS "[SurroundAnimation]" '
    'OR eventMessage CONTAINS[c] "animation" '
    'OR eventMessage CONTAINS[c] "keyboard" '
    'OR eventMessage CONTAINS[c] "menu" '
    'OR eventMessage CONTAINS[c] "completion" '
    'OR eventMessage CONTAINS[c] "idle")'
)
LOG_LINE = re.compile(
    r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+\S+\s+(\S+?)\[(\d+):[0-9a-fA-F]+\]\s+"
    r"(?:\[([^\]]+)\]\s+)?(.*)$"
)
IDLE_REQUEST = "Received request to notify when animations are idle"
IDLE_REPLY = "Sending animations idle reply"
INPUT_TRANSITION = re.compile(r"state transition|Posted notification (?:will|did)(?:Show|Hide)|[Mm]enu")
NATIVE_BEGIN = "[SurroundNativeResizeCapture] BEGIN cycle=1"
NATIVE_ACTION = "[SurroundNativeResizeCapture] ACTION cycle=1"
NATIVE_RESTORED = "[SurroundNativeResizeCapture] RESTORED cycle=1"
NATIVE_TEST = re.compile(
    r"Test Case '-\[SurroundUITests\.GameContinuityUITests "
    r"testMovePreviewKeepsAnExitAcrossLayouts\]' started\."
)


class NativeResizeDetector:
    """Explicit native-test markers only; never changes the test's scheduling."""
    def __init__(self):
        self.active = False
        self.fired = False
        self.action = threading.Event()
        self.restored = threading.Event()
        self.finished = threading.Event()
        self.markers = {}

    def feed(self, line, now):
        if re.search(r"Test Case .+ started\.", line):
            self.active = bool(NATIVE_TEST.search(line))
        if not self.active:
            return None
        if re.search(r"Test Case .+ (passed|failed|skipped|exceeded execution)", line):
            self.finished.set()
            self.active = False
        elif line.strip() == NATIVE_BEGIN and not self.fired:
            self.fired = True
            self.markers["beginReceivedAtUTC"] = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"
            return {"reason": "native-full-screen", "phase": "cycle-1",
                    "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        elif self.fired and line.strip() == NATIVE_ACTION:
            self.markers["actionReceivedAtUTC"] = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"
            self.action.set()
        elif self.fired and line.strip() == NATIVE_RESTORED:
            self.markers["restoredReceivedAtUTC"] = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"
            self.restored.set()
        return None


def summarize_animation_idle(simulator_log, console_log):
    """Pair XCTest's in-app animation-idle requests with replies, per app process.

    An unanswered request is what XCTest later reports as a missing animation
    completion. Reads the collected logs only; never touches the simulator.
    """
    summary = {"requests": 0, "replies": 0, "repliesWithError": 0, "unanswered": [],
               "consoleAnimationCompletionWarnings": None}
    try:
        summary["consoleAnimationCompletionWarnings"] = sum(
            WARNING in line for line in Path(console_log).read_text(errors="replace").splitlines())
    except OSError as error:
        summary["consoleError"] = str(error)
    try:
        lines = Path(simulator_log).read_text(errors="replace").splitlines()
    except OSError as error:
        summary["error"] = str(error)
        return summary

    events = []
    for line in lines:
        match = LOG_LINE.match(line)
        if match:
            stamp, process, pid, category, message = match.groups()
            events.append((stamp, process, int(pid), category or "", message))

    def elapsed(later, earlier):
        form = "%Y-%m-%d %H:%M:%S.%f"
        return round((datetime.strptime(later, form) - datetime.strptime(earlier, form)).total_seconds(), 3)

    pending, transitions, unanswered = {}, {}, []
    for index, (stamp, process, pid, category, message) in enumerate(events):
        if process != "Surround":
            continue
        if ("UIKit" in category or "TextInputUI" in category) and INPUT_TRANSITION.search(message):
            transitions[pid] = (transitions.get(pid, []) + [stamp + " " + message[:120]])[-3:]
        if not category.startswith("com.apple.dt.xctest"):
            continue
        if message.startswith(IDLE_REQUEST):
            summary["requests"] += 1
            if pid in pending:
                unanswered.append(pending[pid])
            pending[pid] = (index, stamp, pid, list(transitions.get(pid, [])))
        elif message.startswith(IDLE_REPLY):
            summary["replies"] += 1
            if "error: (null)" not in message:
                summary["repliesWithError"] += 1
            pending.pop(pid, None)
    unanswered.extend(pending.values())

    for index, stamp, pid, preceding in sorted(unanswered):
        following = next((event for event in events[index + 1:]
                          if event[2] == pid and event[3].startswith("com.apple.dt.xctest")), None)
        summary["unanswered"].append({
            "requestedAt": stamp,
            "pid": pid,
            "precedingInputTransitions": preceding,
            # Roughly XCTest's 60-second allowance when the reply never came; None
            # when the log ended first, for example because the app was terminated.
            "secondsUntilNextXCTestActivity": elapsed(following[0], stamp) if following else None,
        })
    return summary


class StallDetector:
    def __init__(self, seconds):
        self.seconds = seconds
        self.test = None
        self.arm_source = None
        self.wait_since = None
        self.fired = False

    def feed(self, line, now):
        if re.search(r"Test Case .+ started\.", line):
            self.test = line.strip()
            self.arm_source = None
            self.wait_since = None
        elif re.search(r"Test Case .+ (passed|failed|skipped|exceeded execution)", line):
            self.test = None
            self.arm_source = None
            self.wait_since = None
        if not self.test or self.fired:
            return None
        activity = ACTIVITY.match(line)
        description = activity.group(1).strip() if activity else None
        if ARM_MARKER in line or (description and re.match(
            r'Tap "game\.analyze\.share"(?:\s|$)', description
        )):
            self.arm_source = line.strip()
        # The missing completion notification is the stall signature itself,
        # and a stall can begin without any Share action (compact chat's board
        # toggle, for one). Capture it in any test. Only the shorter idle-wait
        # threshold needs Share arming, so an ordinary slow wait elsewhere
        # cannot spend the run's single capture.
        if WARNING in line:
            return self._fire("missing-animation-completion", now)
        if EVENT_LOOP_WARNING in line:
            return self._fire("missing-event-loop-idle", now)
        if not self.arm_source:
            return None
        if description == IDLE:
            # Duplicate reports are not proof that the UI made progress.
            if self.wait_since is None:
                self.wait_since = now
        elif description:
            self.wait_since = None
        return self.check(now)

    def check(self, now):
        if not self.fired and self.wait_since is not None and now - self.wait_since >= self.seconds:
            return self._fire("long-idle-wait", now)
        return None

    def _fire(self, reason, now):
        self.fired = True
        return {"reason": reason, "test": self.test, "armSource": self.arm_source,
                "idleSeconds": None if self.wait_since is None else now - self.wait_since,
                "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}


def stop_owned_process(process):
    """Only for a collector started with start_new_session=True, never the test."""
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=2)
    except ProcessLookupError:
        pass


def tool(command, output, timeout, stop=None, limit=2 * 1024 * 1024,
         on_line=None, env=None, cleanup=None):
    """Run a bounded, owned collector, keeping output and nonfatal errors."""
    started = time.monotonic()
    result = {"command": command, "output": str(output), "exitCode": None}
    process = None
    pending = b""
    clean = cleanup or stop_owned_process
    try:
        with open(output, "wb", buffering=0) as stream:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       start_new_session=True, env=env)
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                written = 0
                while selector.get_map():
                    if stop is not None and stop.is_set():
                        result["stopped"] = "wrapper-finished"
                        break
                    if time.monotonic() - started >= timeout:
                        result["error"] = "collector timeout"
                        break
                    for key, _ in selector.select(0.1):
                        data = os.read(key.fd, 65536)
                        if not data:
                            selector.unregister(key.fileobj)
                            continue
                        remaining = max(0, limit - written)
                        stream.write(data[:remaining])
                        written += len(data)
                        if on_line:
                            pending += data
                            while b"\n" in pending:
                                line, pending = pending.split(b"\n", 1)
                                on_line(line.decode("utf-8", errors="replace"))
                            pending = pending[-65536:]
                        if written > limit:
                            result["error"] = "collector output limit"
                            break
                    if result.get("error"):
                        break
                # A collector may close its output before exiting.
                remaining = max(0.1, timeout - (time.monotonic() - started))
                if not result.get("error") and not result.get("stopped"):
                    try:
                        process.wait(timeout=remaining)
                    except subprocess.TimeoutExpired:
                        result["error"] = "collector timeout after output closed"
            metadata = clean(process)
            if metadata:
                result["cleanup"] = metadata
            result["exitCode"] = process.returncode
            if process.returncode and not result.get("error") and not result.get("stopped"):
                result["error"] = "collector exited unsuccessfully"
    except (OSError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    finally:
        if process is not None:
            metadata = clean(process)
            if metadata:
                result["cleanup"] = metadata
            process.stdout.close()
        result["elapsedSeconds"] = round(time.monotonic() - started, 3)
    return result


def stop_native_collector(process, deadline, privileged=False):
    """Clean only our collector group or sudo wrapper, never the sampled app."""
    if process.poll() is not None:
        return {"stopped": True}
    result = {"pid": process.pid, "stopped": False}
    available = deadline - time.monotonic()
    if available <= 0:
        result["error"] = "Cleanup deadline exhausted; collector exit unconfirmed"
        return result
    try:
        if privileged:
            # Signal only our unreaped sudo child; sudo relays TERM to its
            # command even when it created a separate pty/session. KILL would
            # not be relayed. Wrapper exit alone does not prove sampler exit;
            # spindump's intrinsic limit remains the primary command bound.
            result["collectorExitConfirmed"] = False
            command = ["sudo", "-n", "/bin/kill", "-TERM", str(process.pid)]
            killed = subprocess.run(command, capture_output=True,
                                    timeout=min(0.5, available))
            result["exitCode"] = killed.returncode
            if killed.returncode:
                result["error"] = "Noninteractive privileged collector cleanup failed"
        else:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=min(0.2, available))
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
        available = deadline - time.monotonic()
        if available > 0:
            process.wait(timeout=min(0.2, available))
        result["stopped"] = process.poll() is not None
        if not result["stopped"]:
            result.setdefault("error", "Collector exit unconfirmed")
    except ProcessLookupError:
        result["stopped"] = process.poll() is not None
    except (OSError, subprocess.SubprocessError) as error:
        result.setdefault("error", str(error))
        result["cleanupException"] = str(error)
    if privileged:
        result["wrapperStopped"] = result["stopped"]
    return result


def simulator_pids(text):
    """Only exact application jobs from the supplied simulator's launchctl."""
    found = {}
    for line in text.splitlines():
        fields = line.split(None, 2)
        if len(fields) != 3 or not fields[0].isdigit() or int(fields[0]) <= 0:
            continue
        for role, bundle in (("app", APP), ("runner", RUNNER)):
            if re.fullmatch(r"UIKitApplication:" + re.escape(bundle) + r"(?:\[[^\]\s]+\])+", fields[2]):
                if role in found:
                    raise ValueError("Multiple matching " + role + " jobs; refusing to guess")
                found[role] = {"pid": int(fields[0]), "label": fields[2]}
    return found


def capture(args, output, stop):
    directory = output / "early-capture"
    directory.mkdir()
    result = {"simulator": args.simulator, "tools": {}, "processes": {}}
    launchctl = tool(["xcrun", "simctl", "spawn", args.simulator, "launchctl", "list"],
                     directory / "launchctl.log", args.capture_timeout, stop)
    result["tools"]["launchctl"] = launchctl
    if launchctl.get("exitCode") == 0 and not launchctl.get("error"):
        try:
            result["processes"] = simulator_pids((directory / "launchctl.log").read_text())
        except ValueError as error:
            result["error"] = str(error)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {}
        for role in ("app", "runner"):
            process = result["processes"].get(role)
            if not process:
                result["tools"][role] = {"error": "No exact simulator launchctl job; sample skipped"}
                continue
            command = ["sample", str(process["pid"]), str(args.sample_seconds), "10", "-file",
                       str(directory / (role + ".sample.txt"))]
            futures[role] = pool.submit(tool, command, directory / (role + ".sample-command.log"),
                                        args.capture_timeout, stop)
        futures["screenshot"] = pool.submit(
            tool, ["xcrun", "simctl", "io", args.simulator, "screenshot", str(directory / "simulator.png")],
            directory / "screenshot.log", args.capture_timeout, stop)
        for role, future in futures.items():
            result["tools"][role] = future.result()
    return result


def capture_native_resize(args, output, stop, detector):
    """One device recording and raw app sample, outside XCTest/AX, within one budget.

    Stackshots briefly perturb scheduling. This evidence cannot establish that an
    instrumented pass would also pass without collection. No app or runner is signalled.
    """
    started = time.monotonic()
    deadline = started + args.native_capture_seconds
    # Reserve time for SIGINT to finalize the MP4 rather than force-cutting it.
    work_deadline = deadline - min(2, args.native_capture_seconds / 4)
    directory = output / "native-full-screen"
    directory.mkdir()
    result = {"simulator": args.simulator, "tools": {}, "processes": {},
              "budgetSeconds": args.native_capture_seconds,
              "startedAtUTC": datetime.utcnow().isoformat(timespec="milliseconds") + "Z",
              "instrumentation": "Independent compositor recording and targeted stackshot; may perturb scheduling"}
    video = None
    video_log = None

    def remaining():
        return max(0, work_deadline - time.monotonic())

    def collect(command, name, maximum=None):
        # Leave owned-process cleanup time inside the same work deadline.
        budget = max(0, remaining() - 0.5)
        if maximum is not None:
            budget = min(budget, maximum)
        if budget <= 0:
            return {"error": "shared capture deadline exhausted"}
        cleanup_result = {}

        def clean(process):
            if not cleanup_result:
                cleanup_result.update(stop_native_collector(process, work_deadline))
            return cleanup_result

        return tool(command, directory / name, budget, stop, cleanup=clean)

    try:
        video_command = ["xcrun", "simctl", "io", args.simulator, "recordVideo",
                         "--codec=h264", str(directory / "compositor.mp4")]
        video_log = open(directory / "video.log", "wb", buffering=0)
        video = subprocess.Popen(video_command, stdout=video_log, stderr=subprocess.STDOUT,
                                 start_new_session=True)
        result["video"] = {"command": video_command, "pid": video.pid,
                           "output": str(directory / "compositor.mp4")}
        while not detector.action.is_set() and not detector.finished.is_set() and not stop.is_set():
            if remaining() <= 0:
                break
            detector.action.wait(min(0.1, remaining()))
        result["actionObserved"] = detector.action.is_set()
        if not result["actionObserved"]:
            result["error"] = "Full Screen ACTION marker absent before capture deadline or test end"
            return result

        result["tools"]["launchctl"] = collect(
            ["xcrun", "simctl", "spawn", args.simulator, "launchctl", "list"], "launchctl.log", 3)
        launchctl = result["tools"]["launchctl"]
        if launchctl.get("exitCode") == 0 and not launchctl.get("error"):
            try:
                result["processes"] = simulator_pids((directory / "launchctl.log").read_text())
            except ValueError as error:
                result["error"] = str(error)
        app = result["processes"].get("app")
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            futures = {
                "screenshot": pool.submit(collect,
                    ["xcrun", "simctl", "io", args.simulator, "screenshot",
                     str(directory / "post-action.png")], "screenshot.log", 3),
            }
            if app:
                pid = str(app["pid"])
                futures["process"] = pool.submit(collect,
                    ["ps", "-p", pid, "-o", "pid=,ppid=,state=,pcpu=,etime=,comm="], "process.log", 2)
                # Intrinsic root-command limit is shorter than the shared deadline.
                # No symbolization while sampling; keep UUID/offset binary data.
                raw_limit = min(12, int(remaining() - 2))
                if raw_limit >= args.native_stack_seconds + 1:
                    raw_command = ["sudo", "-n", "/usr/sbin/spindump", pid,
                                   str(args.native_stack_seconds), "10", "-onlyTarget",
                                   "-noSymbolicate", "-noText", "-timelimit", str(raw_limit),
                                   "-o", str(directory / "app.raw.spindump")]
                    # Allow its intrinsic limit to complete even if XCTest exits;
                    # a user-owned wrapper cannot assume it can signal a root child.
                    raw_cleanup = {}

                    def clean_raw(process):
                        if not raw_cleanup:
                            raw_cleanup.update(stop_native_collector(process, work_deadline, privileged=True))
                        return raw_cleanup

                    result["sampleRequestedAtUTC"] = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"
                    futures["rawStack"] = pool.submit(tool, raw_command,
                        directory / "raw-stack.log", raw_limit + 1, None, cleanup=clean_raw)
                else:
                    result["tools"]["rawStack"] = {"error": "Insufficient shared budget for raw sampling"}
            else:
                result["tools"]["rawStack"] = {"error": "No exact simulator app job; raw sample skipped"}
            for name, future in futures.items():
                try:
                    result["tools"][name] = future.result()
                except Exception as error:
                    result["tools"][name] = {"error": str(error)}
            raw = result["tools"].get("rawStack", {})
            raw["artifactExists"] = (directory / "app.raw.spindump").is_file()
            if raw.get("exitCode") == 0 and not raw["artifactExists"]:
                raw["error"] = "Raw sampler returned success without an artifact"
        # Continue compositor observation through restoration (or the same
        # deadline), including when sampling is unavailable. Never delay XCTest.
        while not detector.restored.is_set() and not detector.finished.is_set() and not stop.is_set():
            if remaining() <= 0:
                break
            detector.restored.wait(min(0.1, remaining()))
        result["restoredMarkerObserved"] = detector.restored.is_set()
    except (OSError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    finally:
        if video is not None:
            details = result["video"]
            if video.poll() is None:
                try:
                    os.killpg(video.pid, signal.SIGINT)
                    details["finalizationSignal"] = "owned-recorder-SIGINT"
                    available = deadline - time.monotonic() - min(0.7, args.native_capture_seconds / 8)
                    if available > 0:
                        video.wait(timeout=min(1, available))
                    if video.poll() is None:
                        raise subprocess.TimeoutExpired(video.args, 1)
                except subprocess.TimeoutExpired:
                    details["error"] = "Recorder did not finalize within shared deadline"
                    details["cleanup"] = stop_native_collector(video, deadline)
                except ProcessLookupError:
                    pass
                except OSError as error:
                    details["error"] = str(error)
            details["exitCode"] = video.poll()
            details["artifactExists"] = (directory / "compositor.mp4").is_file()
            if not details["artifactExists"]:
                details.setdefault("error", "No compositor video artifact")
        if video_log is not None:
            video_log.close()
        result["elapsedSeconds"] = round(time.monotonic() - started, 3)
        result["markers"] = dict(detector.markers)
        (directory / "capture.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def log_stream(args, output, stop):
    # A guest log process can outlive its host simctl. Record an ownership nonce
    # and its exact PID; native --timeout also bounds an unverifiable orphan.
    owner = uuid.uuid4().hex
    guest_pid = None

    def receive(line):
        nonlocal guest_pid
        match = re.fullmatch(r"SurroundAnimationCollectorPID=(\d+)", line)
        if match:
            guest_pid = int(match.group(1))

    environment = os.environ.copy()
    environment["SIMCTL_CHILD_SURROUND_ANIMATION_LOG_OWNER"] = owner
    predicate = LOG_PREDICATE
    if getattr(args, "native_resize_capture", False):
        predicate = "(" + predicate + ") OR " + (
            '(process == "Surround" AND '
            '(eventMessage CONTAINS[c] "main run loop" '
            'OR eventMessage CONTAINS "XCTPerformOnMainRunLoop")) OR '
            '(process IN {"runningboardd", "SpringBoard"} '
            'AND eventMessage CONTAINS "com.honganhkhoa.Surround")'
        )
    command = ["xcrun", "simctl", "spawn", args.simulator, "/bin/sh", "-c",
               'printf "SurroundAnimationCollectorPID=%s\\n" "$$"; export DYLD_ROOT_PATH="$SIMULATOR_ROOT"; exec "$SIMULATOR_ROOT/usr/bin/log" stream "$@"',
               "surround-animation-log", "--style", "compact", "--level", "debug",
               "--timeout", str(args.log_seconds), "--predicate", predicate]
    result = tool(command, output / "simulator.log", args.log_seconds + 5, stop,
                  args.log_max_bytes, receive, environment)
    result["guestPID"] = guest_pid
    if guest_pid:
        # Never retain environment contents. Verify ownership immediately before
        # signalling only our log process, not any simulator app or test runner.
        try:
            check = subprocess.run(["ps", "eww", "-p", str(guest_pid), "-o", "command="],
                                   capture_output=True, text=True, timeout=3)
            if check.returncode == 1 and not check.stdout.strip():
                result["guestCleanup"] = "already-exited"
            elif (check.returncode == 0 and "/usr/bin/log stream " in check.stdout
                  and re.search(r"(?:^|\s)SIMULATOR_UDID=" + re.escape(args.simulator) + r"(?:\s|$)", check.stdout, re.I)
                  and re.search(r"(?:^|\s)SURROUND_ANIMATION_LOG_OWNER=" + owner + r"(?:\s|$)", check.stdout)):
                os.kill(guest_pid, signal.SIGTERM)
                result["guestCleanup"] = "owned-log-SIGTERM"
            else:
                result["guestCleanupError"] = "Ownership unverified; no guest signal sent; native log timeout remains"
        except ProcessLookupError:
            result["guestCleanup"] = "already-exited"
        except (OSError, subprocess.SubprocessError) as error:
            result["guestCleanupError"] = str(error)
    elif result.get("stopped") or result.get("error"):
        result["guestCleanupError"] = "Guest PID unavailable; native log timeout remains"
    return result


def run(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    stop = threading.Event()
    status = {"simulator": args.simulator, "command": args.command, "capture": None,
              "nativeResizeCapture": None,
              "commandExitCode": None, "errors": []}
    detector = StallDetector(args.stall_seconds)
    native_detector = NativeResizeDetector()
    command = None
    interrupted = None
    interrupt_time = None
    capture_future = None
    native_future = None
    previous_handlers = {}

    def interrupted_by(signum, _frame):
        nonlocal interrupted, interrupt_time
        if interrupted is None:
            interrupted, interrupt_time = signum, time.monotonic()
            stop.set()
            if command is not None and command.poll() is None:
                try:
                    command.send_signal(signum)  # Exact wrapped PID, no process-group or runner signal.
                except ProcessLookupError:
                    pass

    def maybe_capture(trigger, pool):
        nonlocal capture_future
        if trigger and capture_future is None and not stop.is_set():
            status["trigger"] = trigger
            print("[SurroundAnimation] Capturing one early idle-wait diagnostic.", file=sys.stderr, flush=True)
            capture_future = pool.submit(capture, args, output, stop)

    def maybe_native_capture(line, pool):
        nonlocal native_future
        if not getattr(args, "native_resize_capture", False):
            return
        trigger = native_detector.feed(line, time.monotonic())
        if trigger and native_future is None and not stop.is_set():
            status["nativeResizeTrigger"] = trigger
            print("[SurroundNativeResizeCapture] Starting bounded independent capture.", file=sys.stderr, flush=True)
            native_future = pool.submit(capture_native_resize, args, output, stop, native_detector)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[signum] = signal.signal(signum, interrupted_by)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            log_future = pool.submit(log_stream, args, output, stop)
            try:
                with open(output / "console.log", "wb", buffering=0) as console:
                    command = subprocess.Popen(args.command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                               bufsize=0, start_new_session=True)
                    pending = b""
                    console_open = True
                    command_exited_at = None
                    with selectors.DefaultSelector() as selector:
                        selector.register(command.stdout, selectors.EVENT_READ)
                        while selector.get_map() or command.poll() is None:
                            if command.poll() is not None:
                                stop.set()
                                if command_exited_at is None:
                                    command_exited_at = time.monotonic()
                                elif selector.get_map() and time.monotonic() - command_exited_at >= 2:
                                    status["errors"].append("Console drain stopped after command exit; another process retained stdout")
                                    break
                            if interrupted and time.monotonic() - interrupt_time >= 5:
                                status["errors"].append("Wrapped command did not exit within signal grace; no force-kill sent")
                                break
                            for key, _ in selector.select(0.1):
                                data = os.read(key.fd, 65536)
                                if not data:
                                    selector.unregister(key.fileobj)
                                    continue
                                console.write(data)
                                if console_open:
                                    try:
                                        sys.stdout.buffer.write(data)
                                        sys.stdout.buffer.flush()
                                    except BrokenPipeError:
                                        console_open = False
                                        status["errors"].append("Console consumer closed; raw console.log continues")
                                pending += data
                                while b"\n" in pending:
                                    line, pending = pending.split(b"\n", 1)
                                    decoded = line.decode("utf-8", errors="replace")
                                    maybe_native_capture(decoded, pool)
                                    maybe_capture(detector.feed(decoded, time.monotonic()), pool)
                                # An oversized non-line diagnostic must not grow watcher memory forever.
                                pending = pending[-1024 * 1024:]
                            if command.poll() is None:
                                maybe_capture(detector.check(time.monotonic()), pool)
                        command.stdout.close()
                    if command.poll() is not None:
                        status["commandExitCode"] = command.returncode
            except OSError as error:
                status["errors"].append(str(error))
                status["commandExitCode"] = 127
            finally:
                stop.set()
                try:
                    status["simulatorLog"] = log_future.result()
                except Exception as error:
                    status["simulatorLog"] = {"error": str(error)}
                if capture_future is not None:
                    try:
                        status["capture"] = capture_future.result()
                    except Exception as error:
                        status["capture"] = {"error": str(error)}
                if native_future is not None:
                    try:
                        status["nativeResizeCapture"] = native_future.result()
                    except Exception as error:
                        status["nativeResizeCapture"] = {"error": str(error)}
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        status["signal"] = interrupted
        code = status["commandExitCode"]
        status["exitCode"] = 128 + interrupted if interrupted else (128 - code if code is not None and code < 0 else code)
        try:
            status["animationIdle"] = summarize_animation_idle(output / "simulator.log", output / "console.log")
        except Exception as error:  # A summary failure must never mask the wrapped exit status.
            status["animationIdle"] = {"error": str(error)}
        idle = status["animationIdle"]
        if "requests" in idle:
            print("[SurroundAnimation] Animation-idle requests={} replies={} unanswered={} consoleWarnings={}".format(
                idle["requests"], idle["replies"], len(idle["unanswered"]),
                idle["consoleAnimationCompletionWarnings"]), file=sys.stderr, flush=True)
        (output / "status.json").write_text(json.dumps(status, indent=2) + "\n")
    return status["exitCode"] if status["exitCode"] is not None else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--output", required=True, help="Fresh artifact directory")
    parser.add_argument("--stall-seconds", type=float, default=15)
    parser.add_argument("--sample-seconds", type=int, default=2)
    parser.add_argument("--capture-timeout", type=float, default=10)
    parser.add_argument("--log-seconds", type=int, default=1800)
    parser.add_argument("--log-max-bytes", type=int, default=16 * 1024 * 1024)
    parser.add_argument("--native-resize-capture", action="store_true",
                        help="Capture only the first explicitly marked native Full Screen restoration")
    parser.add_argument("--native-capture-seconds", type=float, default=20,
                        help="Shared native collector budget, including recorder finalization")
    parser.add_argument("--native-stack-seconds", type=int, default=2)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.simulator):
        parser.error("--simulator must be an exact UUID, never 'booted'")
    if args.command and args.command[0] == "--":
        args.command.pop(0)
    if not args.command:
        parser.error("Supply the test command after --")
    if not (0 < args.stall_seconds <= 120 and 1 <= args.sample_seconds <= 5
            and 0 < args.capture_timeout <= 30 and 1 <= args.log_seconds <= 7200
            and 1024 <= args.log_max_bytes <= 64 * 1024 * 1024
            and 1 <= args.native_capture_seconds <= 20 and 1 <= args.native_stack_seconds <= 5):
        parser.error("Diagnostic limits out of bounds")
    try:
        return run(args)
    except FileExistsError:
        parser.error("--output already exists; choose a fresh directory")


if __name__ == "__main__":
    sys.exit(main())
