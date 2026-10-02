#!/usr/bin/env python3
"""Branch-only external observation of one unchanged forced-layout XCTest.

The five-second marker-region trigger is slow observation evidence. It does not
diagnose an app stall. No input, AX query or screenshot is added at the trigger.
"""
import argparse
import concurrent.futures
import importlib.util
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

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "animation_collectors", Path(__file__).with_name("diagnose-ipad-animation-stalls.py")
)
collectors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collectors)

TARGET = "testChatVariationPreviewKeepsAnExitAcrossLayouts"
SELECTOR = "SurroundUITests/GameContinuityUITests/" + TARGET
CASE = re.compile(r"Test Case '-\[SurroundUITests\.GameContinuityUITests (\w+)\]' (started|passed|failed|skipped|exceeded execution)")
ACTIVITY = re.compile(r"\bt\s*=\s*([0-9.]+)s\s+(.+)$")
SERVICE_LABELS = {"testmanager": "com.apple.testmanagerd", "accessibilityUI": "com.apple.AccessibilityUIServer"}
EXECUTABLES = {"app": "Surround", "runner": "SurroundUITests-Runner", "testmanager": "testmanagerd", "accessibilityUI": "AccessibilityUIServer"}


def anchor():
    return {"epoch": time.time(), "uptime": time.monotonic(),
            "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}


class LayoutWatchdog:
    def __init__(self, seconds=5, cache=None):
        self.seconds = seconds
        self.cache = cache
        self.lock = threading.RLock()
        self.test = None
        self.compact_seen = False
        self.arm_source = None
        self.wait_since = None
        self.fired = False
        self.phase = "inactive"
        self.history = []

    def record(self, phase, raw, now):
        self.phase = phase
        activity = ACTIVITY.search(raw)
        self.history.append({"phase": phase, "observedUptime": now,
            "observedEpoch": time.time(), "nativeRelativeSeconds": float(activity.group(1)) if activity else None,
            "raw": raw.rstrip()})

    def feed(self, line, now):
        with self.lock:
            boundary = CASE.search(line)
            if boundary:
                name, outcome = boundary.groups()
                if outcome == "started":
                    self.test = line.strip() if name == TARGET else None
                    self.compact_seen = False
                    self.arm_source = None
                    self.wait_since = None
                    self.record("case-start" if self.test else "other-case", line, now)
                    if self.test and self.cache:
                        try:
                            self.cache.start()
                        except Exception as error:
                            self.record("identity-cache-start-error", str(error), now)
                elif self.test and name == TARGET:
                    self.record("case-finish-" + outcome, line, now)
                    self.test = None
                    self.wait_since = None
                    if self.cache:
                        self.cache.freeze()
                return None
            if not self.test:
                return None
            activity = ACTIVITY.search(line)
            if not activity:
                if self.wait_since is not None:
                    self.record(self.phase, line, now)
                return self.check(now)
            description = activity.group(2).strip()
            if description == "Tear Down":
                self.record("teardown", line, now)
                self.wait_since = None
                if self.cache:
                    self.cache.freeze()
                return None
            if re.fullmatch(r'Tap "uitest\.gameLayout\.compact" Button', description):
                self.compact_seen = True
                self.arm_source = None
                self.wait_since = None
                self.record("compact-transition-unarmed", line, now)
            elif re.fullmatch(r'Tap "uitest\.gameLayout\.regular" Button', description) and self.compact_seen:
                self.arm_source = line.strip()
                self.record("regular-tap-awaiting-marker", line, now)
            elif self.arm_source and re.fullmatch(r'Waiting [0-9.]+s for "uitest\.gameLayout\.current" Any to exist', description):
                if self.wait_since is None:
                    self.wait_since = now
                    if self.cache:
                        self.cache.freeze()
                self.record("final-marker-existence", line, now)
            elif self.wait_since is not None:
                if '"game.displayMode"' in description:
                    self.record("subtree-check-marker-region-ended", line, now)
                    self.wait_since = None
                    return None
                if 'label == "regular"' in description and '"uitest.gameLayout.current"' in description:
                    self.record("final-marker-label", line, now)
                elif "Capturing element debug description" in description:
                    self.record("final-marker-debug", line, now)
                else:
                    self.record(self.phase, line, now)
            return self.check(now)

    def active(self):
        with self.lock:
            return self.test is not None and self.wait_since is not None

    def snapshot(self):
        with self.lock:
            return {"test": self.test, "phase": self.phase, "waitSinceUptime": self.wait_since,
                    "fired": self.fired, "history": list(self.history)}

    def check(self, now):
        with self.lock:
            if not self.fired and self.test and self.wait_since is not None and now - self.wait_since >= self.seconds:
                self.fired = True
                return {"reason": "slow-final-regular-marker-observation", "test": self.test,
                    "armSource": self.arm_source, "markerObservationSeconds": now - self.wait_since,
                    "phase": self.phase, "triggerUptime": now,
                    "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            return None


def destination_pids(text):
    found = collectors.simulator_pids(text)
    for line in text.splitlines():
        fields = line.split(None, 2)
        if len(fields) != 3 or not fields[0].isdigit() or int(fields[0]) <= 0:
            continue
        for role, label in SERVICE_LABELS.items():
            if fields[2] == label:
                if role in found:
                    raise ValueError("Ambiguous exact destination service: " + role)
                found[role] = {"pid": int(fields[0]), "label": label}
    return found


def parse_identity(text, role, pid):
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError("Expected exactly one targeted process identity")
    match = re.fullmatch(r"\s*(\d+)\s+(\w{3}\s+\w{3}\s+\d{1,2}\s+\d\d:\d\d:\d\d\s+\d{4})\s+(.+?)\s*", lines[0])
    if not match or int(match.group(1)) != pid:
        raise ValueError("Targeted PID/start time is missing or mismatched")
    command = match.group(3)
    if Path(command).name != EXECUTABLES[role]:
        raise ValueError("Executable does not match the exact destination role")
    return {"pid": pid, "startTime": " ".join(match.group(2).split()), "command": command}


def process_identity(role, process, directory, timeout, stop=None):
    status = collectors.tool(["ps", "-ww", "-p", str(process["pid"]), "-o", "pid=,lstart=,comm="],
                             directory / (role + ".identity.log"), timeout, stop)
    result = {"role": role, "destinationLabel": process["label"], "query": status, "observed": anchor()}
    if status.get("exitCode") == 0 and not status.get("error") and not status.get("stopped"):
        try:
            result["identity"] = parse_identity((directory / (role + ".identity.log")).read_text(), role, process["pid"])
        except (OSError, ValueError) as error:
            result["error"] = str(error)
    else:
        result["error"] = "Targeted process identity unavailable; role skipped"
    return result


class IdentityCache:
    """At most three metadata snapshots before the final marker region."""
    def __init__(self, args, output):
        self.args = args
        self.output = output
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.thread = None
        self.history = []
        self.identities = {}

    def start(self):
        if self.thread is None:
            self.thread = threading.Thread(target=self.run, name="layout-destination-identities")
            self.thread.start()

    def freeze(self):
        self.stop.set()

    def snapshot(self):
        with self.lock:
            return {"identities": dict(self.identities), "history": list(self.history)}

    def run(self):
        try:
            for index in range(1, 4):
                if self.stop.is_set():
                    break
                directory = self.output / "identity-cache" / ("attempt-" + str(index))
                directory.mkdir(parents=True)
                result = {"started": anchor(), "simulator": self.args.simulator, "roles": {}}
                lookup = collectors.tool(["xcrun", "simctl", "spawn", self.args.simulator, "launchctl", "list"],
                                         directory / "launchctl.log", 10, self.stop)
                result["launchctl"] = lookup
                if lookup.get("exitCode") == 0 and not lookup.get("error") and not lookup.get("stopped"):
                    try:
                        found = destination_pids((directory / "launchctl.log").read_text())
                        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                            futures = {role: pool.submit(process_identity, role, value, directory, 5, self.stop)
                                       for role, value in found.items()}
                            for role, future in futures.items():
                                result["roles"][role] = future.result()
                        with self.lock:
                            for role, value in result["roles"].items():
                                if value.get("identity"):
                                    self.identities[role] = value
                    except (OSError, ValueError) as error:
                        result["error"] = str(error)
                result["completed"] = anchor()
                (directory / "status.json").write_text(json.dumps(result, indent=2) + "\n")
                with self.lock:
                    self.history.append(result)
                if self.stop.wait(5):
                    break
        except Exception as error:
            with self.lock:
                self.history.append({"error": str(error), "observed": anchor()})


def sample_role(args, role, cached, directory, deadline, stop):
    result = {"role": role, "started": anchor(), "cached": cached,
              "actualSamplingSecondsRequested": 2}
    remaining = deadline - time.monotonic()
    if remaining < 15 or stop.is_set() or not args.detector.active():
        result["skip"] = "Insufficient bounded window or marker region ended"
        return result
    process = {"pid": cached["identity"]["pid"], "label": cached["destinationLabel"]}
    verified = process_identity(role, process, directory, min(4, remaining - 8), stop)
    result["recheck"] = verified
    if verified.get("identity") != cached["identity"]:
        result["skip"] = "PID/start time/executable identity not reverified"
    elif stop.is_set() or not args.detector.active():
        result["skip"] = "Marker region ended before sampling"
    else:
        result["cpuInterpretation"] = "pcpu is a lifetime average; cumulative CPU time and read anchors are retained before/after sampling"
        result["cpuBeforeAnchor"] = anchor()
        result["cpuBefore"] = collectors.tool(["ps", "-ww", "-p", str(process["pid"]), "-o", "pid=,pcpu=,time=,etime=,stat=,comm="],
                                               directory / (role + ".cpu-before.log"), 2, stop)
        if not stop.is_set() and args.detector.active() and deadline - time.monotonic() >= 5:
            result["sample"] = collectors.tool(
                ["sample", str(process["pid"]), "2", "10", "-file", str(directory / (role + ".sample.txt"))],
                directory / (role + ".sample-command.log"), min(7, deadline - time.monotonic() - 3), stop,
                limit=4 * 1024 * 1024)
            sample_path = directory / (role + ".sample.txt")
            result["sampleOutputBytes"] = sample_path.stat().st_size if sample_path.exists() else 0
            if not stop.is_set() and args.detector.active() and deadline - time.monotonic() >= 5:
                result["cpuAfterAnchor"] = anchor()
                result["cpuAfter"] = collectors.tool(["ps", "-ww", "-p", str(process["pid"]), "-o", "pid=,pcpu=,time=,etime=,stat=,comm="],
                                                     directory / (role + ".cpu-after.log"), 2, stop)
        else:
            result["skip"] = "Marker region ended or processing budget exhausted"
    result["completed"] = anchor()
    return result


def capture_window(args, output, stop):
    directory = output / "marker-window"
    directory.mkdir()
    started = time.monotonic()
    deadline = started + 30
    window_stop = threading.Event()

    def bound_window():
        # Reserve three seconds for cleanup of owned observer process groups.
        while not window_stop.wait(0.05):
            if stop.is_set() or not args.detector.active() or time.monotonic() >= deadline - 3:
                window_stop.set()
                return

    guard = threading.Thread(target=bound_window, name="layout-window-bound", daemon=True)
    guard.start()
    cached = args.identity_cache.snapshot()
    result = {"simulator": args.simulator, "started": anchor(), "windowLimitSeconds": 30,
              "roundLimit": 2, "cache": cached, "rounds": []}
    for index in range(1, 3):
        if stop.is_set() or not args.detector.active() or deadline - time.monotonic() < 15:
            result["stoppedReason"] = "Marker region ended, test exited or remaining window insufficient"
            break
        round_directory = directory / ("round-" + str(index))
        round_directory.mkdir()
        observation = {"started": anchor(), "phase": args.detector.snapshot(), "roles": {}}
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            pending = {}
            for role in EXECUTABLES:
                identity = cached["identities"].get(role)
                if identity is None:
                    observation["roles"][role] = {"skip": "No verified exact destination bootstrap/process identity"}
                else:
                    pending[role] = pool.submit(sample_role, args, role, identity, round_directory, deadline, window_stop)
            for role, future in pending.items():
                try:
                    observation["roles"][role] = future.result()
                except Exception as error:
                    observation["roles"][role] = {"error": str(error)}
        observation["completed"] = anchor()
        result["rounds"].append(observation)
        if index == 1:
            stop.wait(min(1, max(0, deadline - time.monotonic())))
    result["completed"] = anchor()
    result["elapsedSeconds"] = time.monotonic() - started
    result["deadlineExceeded"] = result["elapsedSeconds"] > 30
    window_stop.set()
    guard.join(timeout=0.2)
    (directory / "status.json").write_text(json.dumps(result, indent=2) + "\n")
    return result

def note_log_state(args, key, value):
    with args.log_lock:
        args.log_state[key] = value
        if args.log_state.get("headerObserved") and args.log_state.get("guestPID") is not None:
            args.log_ready.set()


def owned_log_pid(simulator, owner, deadline):
    """Find only our native simulator logger; never retain ps environments."""
    inventory = subprocess.run(
        ["ps", "-ww", "-axo", "pid=,comm="], capture_output=True, text=True,
        timeout=max(0.1, min(10, deadline - time.monotonic()))
    )
    inventory.check_returncode()
    found = []
    for line in inventory.stdout.splitlines():
        if time.monotonic() >= deadline:
            return None
        fields = line.strip().split(None, 1)
        if (len(fields) != 2 or not fields[0].isdigit()
                or not (fields[1] == "log" or fields[1].endswith("/usr/bin/log"))):
            continue
        pid = int(fields[0])
        if verifies_log_owner(pid, simulator, owner, timeout=max(0.1, min(10, deadline - time.monotonic()))):
            found.append(pid)
    if len(found) > 1:
        raise RuntimeError("Multiple owned log processes; refusing to choose")
    return found[0] if found else None

def verifies_log_owner(pid, simulator, owner, timeout=10):
    check = subprocess.run(
        ["ps", "eww", "-p", str(pid), "-o", "command="],
        capture_output=True, text=True, timeout=timeout,
    )
    return check.returncode == 0 and re.search(r"^(?:.*?/)?log stream(?:\s|$)", check.stdout.strip()) and all(
        re.search(r"(?:^|\s)" + name + "=" + re.escape(value) + r"(?:\s|$)", check.stdout, re.I)
        for name, value in (("SIMULATOR_UDID", simulator), ("SURROUND_LAYOUT_LOG_OWNER", owner))
    )

def native_log_stream(args, output, stop):
    owner = uuid.uuid4().hex
    guest_pid = None
    discovery_errors = []
    discovery_timeouts = []

    def discover():
        nonlocal guest_pid
        deadline = time.monotonic() + min(60, args.log_seconds)
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                guest_pid = owned_log_pid(args.simulator, owner, deadline)
                if guest_pid is not None:
                    note_log_state(args, "guestPID", guest_pid)
                    note_log_state(args, "guestPIDObserved", anchor())
                    return
            except subprocess.TimeoutExpired:
                # A finite ps timeout under host load is inconclusive. Retry only
                # within the same ownership deadline; never guess a guest PID.
                discovery_timeouts.append({"observedAtEpoch": time.time(), "reason": "bounded ps timeout"})
            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                discovery_errors.append(str(error))
                return
            stop.wait(0.5)

    def receive(line):
        if "Filtering the log data" in line:
            note_log_state(args, "headerObserved", anchor())

    note_log_state(args, "nativeCommandRequested", anchor())
    environment = os.environ.copy()
    environment["SIMCTL_CHILD_SURROUND_LAYOUT_LOG_OWNER"] = owner
    watcher = threading.Thread(target=discover, name="layout-log-owner")
    watcher.start()
    try:
        # A bare name resolves the runtime's executable through the device PATH.
        # An absolute host /bin/sh is a macOS binary and cannot use this runtime's dyld root.
        command = ["xcrun", "simctl", "spawn", args.simulator, "log", "stream",
                   "--style", "compact", "--level", "debug", "--timeout", str(args.log_seconds),
                   "--predicate", collectors.LOG_PREDICATE]
        result = collectors.tool(command, output / "simulator.log", args.log_seconds + 5,
                                 stop, args.log_max_bytes, on_line=receive, env=environment)
    finally:
        watcher.join(timeout=12)
    result["guestPID"] = guest_pid
    result["ownershipDiscoveryErrors"] = discovery_errors
    result["ownershipDiscoveryTimeouts"] = discovery_timeouts
    if guest_pid is not None:
        try:
            if verifies_log_owner(guest_pid, args.simulator, owner):
                os.kill(guest_pid, signal.SIGTERM)  # Reverified exact owned logger only.
                result["guestCleanup"] = "owned-log-SIGTERM"
            else:
                check = subprocess.run(["ps", "-p", str(guest_pid), "-o", "pid="],
                                       capture_output=True, text=True, timeout=3)
                if check.returncode == 1 and not check.stdout.strip():
                    result["guestCleanup"] = "already-exited"
                else:
                    result["guestCleanupError"] = "Ownership unverified; no signal sent; native timeout remains"
        except ProcessLookupError:
            result["guestCleanup"] = "already-exited"
        except (OSError, subprocess.SubprocessError) as error:
            result["guestCleanupError"] = str(error)
    else:
        result["guestCleanupError"] = "Owned guest PID unavailable; native timeout remains"
    with args.log_lock:
        result["startup"] = dict(args.log_state)
    return result

def start_video(simulator, path, stream):
    return subprocess.Popen(
        ["xcrun", "simctl", "io", simulator, "recordVideo", "--codec=h264", str(path)],
        stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
    )

def await_video(process, log):
    # Hosted preflight now proves a stopped, playable movie. Native help promises
    # this first-frame marker but no 15-second deadline; retain a finite 60s bound.
    started = time.monotonic()
    deadline = started + 60
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Recorder exited before readiness: " + str(process.returncode))
        if "Recording started" in log.read_text(errors="replace"):
            return {"recordingReadyAtEpoch": time.time(), "recordingReadyUptime": time.monotonic(),
                    "recordingStartupSeconds": time.monotonic() - started}
        time.sleep(0.1)
    raise RuntimeError("Recorder did not report a first frame within 60 seconds")

def finish_video(video, path, flush_seconds=10):
    status = {"path": str(path), "errors": []}
    if video.poll() is None:
        try:
            status["stopSignal"] = "SIGINT"
            status["stopRequestedAtEpoch"] = time.time()
            video.send_signal(signal.SIGINT)
            video.wait(timeout=flush_seconds)
        except subprocess.TimeoutExpired:
            status["errors"].append("Video flush timeout")
            collectors.stop_owned_process(video)
        except ProcessLookupError:
            pass
    status["exitCode"] = video.returncode
    status["bytes"] = path.stat().st_size if path.exists() else 0
    if video.returncode != 0:
        status["errors"].append("Recorder exited unsuccessfully")
    if status["bytes"] == 0:
        status["errors"].append("No nonempty video file")
    return status

def validate_collectors(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    args.log_seconds = 90
    stop = threading.Event()
    video_path = output / "native-validation.mp4"
    video = None
    result = {"simulator": args.simulator, "recordingWindowSeconds": 60,
              "startedAtEpoch": time.time(), "testCommandExecuted": False}
    # These read-only observations do not drive the app or change simulator settings.
    commands = {
        "nativeHelp": (["xcrun", "simctl", "io", args.simulator, "recordVideo", "--help"], 15),
        "devices": (["xcrun", "simctl", "list", "devices", "--json"], 15),
        "bootStatus": (["xcrun", "simctl", "bootstatus", args.simulator], 30),
        "screenshot": (["xcrun", "simctl", "io", args.simulator, "screenshot", str(output / "simulator-ready.png")], 30),
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        pending = {name: pool.submit(collectors.tool, command, output / (name + ".log"), timeout)
                   for name, (command, timeout) in commands.items()}
        result["readiness"] = {name: future.result() for name, future in pending.items()}
    # The logger runs independently: a recorder error must not hide its result.
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        logger_started = time.monotonic()
        future = pool.submit(native_log_stream, args, output, stop)
        command = ["xcrun", "simctl", "io", args.simulator, "recordVideo", "--codec=h264", str(video_path)]
        result["videoCommand"] = command
        result["videoObservations"] = []
        try:
            with open(output / "video.stdout.log", "wb", buffering=0) as stdout, open(output / "video.stderr.log", "wb", buffering=0) as stderr:
                video = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
                result["videoPID"] = video.pid
                result["videoStartedAtEpoch"] = time.time()
                started = time.monotonic()
                for index in range(4):
                    if index:
                        stop.wait(max(0, started + index * 20 - time.monotonic()))
                    snapshot = collectors.tool(["ps", "-p", str(video.pid), "-o", "pid=,ppid=,etime=,state=,comm="],
                                               output / ("video-process-" + str(index) + ".log"), 3)
                    result["videoObservations"].append({"atEpoch": time.time(), "poll": video.poll(),
                        "bytes": video_path.stat().st_size if video_path.exists() else 0,
                        "stdoutBytes": (output / "video.stdout.log").stat().st_size,
                        "stderrBytes": (output / "video.stderr.log").stat().st_size,
                        "process": snapshot})
                    if video.poll() is not None:
                        break
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            result["videoError"] = str(error)
        finally:
            if video is not None:
                result["video"] = finish_video(video, video_path, flush_seconds=20)
            # Preserve the independent logger window even if the recorder fails early.
            stop.wait(max(0, logger_started + 60 - time.monotonic()))
            stop.set()
            result["simulatorLog"] = future.result()
    result["readinessMarkerPresent"] = any("Recording started" in path.read_text(errors="replace")
        for path in [output / "video.stdout.log", output / "video.stderr.log"] if path.exists())
    # Decode actual beginning/middle/end frames from the cleanly stopped movie.
    if video_path.exists() and video_path.stat().st_size:
        result["videoDecode"] = collectors.tool(
            ["xcrun", "swift", str(Path(__file__).with_name("verify-diagnostic-video.swift")),
             str(video_path), str(output / "decoded-video")], output / "video-decode.log", 90)
    result["finishedAtEpoch"] = time.time()
    (output / "validation-status.json").write_text(json.dumps(result, indent=2) + "\n")
    logger = result.get("simulatorLog", {})
    valid = (not result.get("videoError") and not result.get("video", {}).get("errors")
             and result.get("videoDecode", {}).get("exitCode") == 0
             and not result.get("videoDecode", {}).get("error")
             and logger.get("guestPID") is not None and not logger.get("error")
             and not logger.get("guestCleanupError") and not logger.get("ownershipDiscoveryErrors")
             and (output / "simulator.log").exists()
             and "Filtering the log data" in (output / "simulator.log").read_text(errors="replace"))
    print(json.dumps(result, indent=2), flush=True)
    return 0 if valid else 1


def run_test_command(args, output, stop):
    """Preserve the original command's exit, even when observer work fails."""
    status = {"simulator": args.simulator, "command": args.command, "capture": None,
              "commandExitCode": None, "testCommandExecuted": False,
              "errors": [], "commandRequested": anchor()}
    command = None
    interrupted = None
    interrupt_time = None
    capture_future = None
    previous_handlers = {}

    def interrupted_by(signum, _frame):
        nonlocal interrupted, interrupt_time
        if interrupted is None:
            interrupted, interrupt_time = signum, time.monotonic()
            stop.set()
            if command is not None and command.poll() is None:
                try:
                    command.send_signal(signum)  # Only the exact wrapped command PID.
                except ProcessLookupError:
                    pass

    def maybe_capture(trigger, pool):
        nonlocal capture_future
        if trigger and capture_future is None and not stop.is_set():
            status["trigger"] = trigger
            try:
                capture_future = pool.submit(capture_window, args, output, stop)
            except Exception as error:
                status["errors"].append("Capture scheduling failed: " + str(error))

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[signum] = signal.signal(signum, interrupted_by)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            try:
                with open(output / "console.log", "wb", buffering=0) as console:
                    command = subprocess.Popen(args.command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                               bufsize=0, start_new_session=True)
                    status["commandSpawned"] = anchor()
                    status["commandPID"] = command.pid
                    status["testCommandExecuted"] = True
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
                                    maybe_capture(args.detector.feed(line.decode("utf-8", errors="replace"), time.monotonic()), pool)
                                pending = pending[-1024 * 1024:]
                            if command.poll() is None:
                                maybe_capture(args.detector.check(time.monotonic()), pool)
                        command.stdout.close()
                    if command.poll() is not None:
                        status["commandExitCode"] = command.returncode
            except OSError as error:
                status["errors"].append(str(error))
                status["commandExitCode"] = 127
            finally:
                stop.set()
                args.identity_cache.freeze()
                if capture_future is not None:
                    try:
                        status["capture"] = capture_future.result()
                    except Exception as error:
                        status["capture"] = {"error": str(error)}
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        status["signal"] = interrupted
        code = status["commandExitCode"]
        status["exitCode"] = 128 + interrupted if interrupted else (128 - code if code is not None and code < 0 else code)
        status["commandCompleted"] = anchor()
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--validate-collectors", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.simulator):
        parser.error("Use an exact simulator UUID")
    if args.command and args.command[0] == "--":
        args.command.pop(0)
    if not args.validate_collectors:
        selected = [value.split(":", 1)[1] for value in args.command if value.startswith("-only-testing:")]
        if selected != [SELECTOR] or "test-without-building" not in args.command:
            parser.error("Supply one unchanged test-without-building command selecting only " + SELECTOR)
    output = Path(args.output).resolve()
    if output.exists():
        parser.error("Use a fresh output directory; do not overwrite evidence")
    output.parent.mkdir(parents=True, exist_ok=True)
    args.log_seconds = 1800
    args.log_max_bytes = 32 * 1024 * 1024
    args.log_lock = threading.Lock()
    args.log_state = {}
    args.log_ready = threading.Event()
    collectors.LOG_PREDICATE = 'process IN {"Surround", "SurroundUITests-Runner", "testmanagerd", "AccessibilityUIServer"}'
    if args.validate_collectors:
        return validate_collectors(args)

    video_path = output.parent / "Layout-native.mp4"
    if video_path.exists():
        parser.error("Movie path exists; do not overwrite evidence")
    output.mkdir()
    stop = threading.Event()
    args.identity_cache = IdentityCache(args, output)
    args.detector = LayoutWatchdog(5, args.identity_cache)
    video = None
    video_status = {"path": str(video_path), "errors": [], "requested": anchor()}
    status = None
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        logger_requested = time.monotonic()
        logger = pool.submit(native_log_stream, args, output, stop)
        with open(output.parent / "Layout-video.log", "wb", buffering=0) as video_log:
            try:
                video = start_video(args.simulator, video_path, video_log)
                video_status["processSpawned"] = anchor()
                video_status.update(await_video(video, output.parent / "Layout-video.log"))
            except (OSError, RuntimeError) as error:
                video_status["errors"].append(str(error))
            # Bounded logger identity/header readiness is explicit before the test.
            ready = args.log_ready.wait(max(0, logger_requested + 60 - time.monotonic()))
            note_log_state(args, "prelaunchReadiness", {"ready": ready, "observed": anchor(),
                "limitSeconds": 60, "error": None if ready else "Native header/owned PID readiness not established before deadline"})
            video_live = video is not None and video.poll() is None
            logger_live = not logger.done()
            note_log_state(args, "prelaunchLiveness", {"videoAlive": video_live, "loggerFutureAlive": logger_live,
                                                        "observed": anchor()})
            try:
                if ready and video_live and logger_live and not video_status["errors"]:
                    status = run_test_command(args, output, stop)
                else:
                    status = {"simulator": args.simulator, "command": args.command,
                        "capture": None, "commandExitCode": None, "testCommandExecuted": False,
                        "exitCode": 1, "prelaunchError": "Native video/logger readiness failed; no test invocation started",
                        "errors": list(video_status["errors"]) + ([] if ready else ["Native logger readiness deadline exceeded"])
                            + ([] if video_live else ["Native recorder is not alive before test launch"])
                            + ([] if logger_live else ["Native logger finished before test launch"])}
            finally:
                stop.set()
                args.identity_cache.freeze()
                if args.identity_cache.thread is not None:
                    args.identity_cache.thread.join(timeout=20)
                if video is not None:
                    try:
                        ended = finish_video(video, video_path)
                    except Exception as error:
                        ended = {"path": str(video_path), "errors": ["Recorder cleanup failed: " + str(error)]}
                    ended["errors"] = video_status["errors"] + ended["errors"]
                    ended.update({key: value for key, value in video_status.items() if key.startswith("recording")})
                    ended.update({key: video_status[key] for key in ["requested", "processSpawned"] if key in video_status})
                    video_status = ended
                try:
                    log_result = logger.result()
                except Exception as error:
                    log_result = {"error": str(error)}
                # Decoder errors are evidence failures and preserve the original exit.
                try:
                    if video_path.exists() and video_path.stat().st_size:
                        video_status["decode"] = collectors.tool(
                            ["xcrun", "swift", str(Path(__file__).with_name("verify-diagnostic-video.swift")),
                             str(video_path), str(output / "decoded-video")], output / "video-decode.log", 90)
                        if video_status["decode"].get("error") or video_status["decode"].get("exitCode") != 0:
                            video_status["errors"].append("Stopped capture movie decode failed; see retained decoder status")
                    else:
                        video_status["errors"].append("No nonempty capture movie to decode")
                except Exception as error:
                    video_status["errors"].append("Movie decode observation failed: " + str(error))
                try:
                    (output / "video-status.json").write_text(json.dumps(video_status, indent=2) + "\n")
                except OSError as error:
                    print("[SurroundLayout] Video evidence write failed: " + str(error), file=sys.stderr)
                if status is not None:
                    status["simulatorLog"] = log_result
                    status["identityCache"] = args.identity_cache.snapshot()
                    status["watchdog"] = args.detector.snapshot()
                    try:
                        (output / "status.json").write_text(json.dumps(status, indent=2) + "\n")
                    except OSError as error:
                        print("[SurroundLayout] Capture evidence write failed: " + str(error), file=sys.stderr)
    return status["exitCode"] if status and status["exitCode"] is not None else 1


if __name__ == "__main__":
    sys.exit(main())
