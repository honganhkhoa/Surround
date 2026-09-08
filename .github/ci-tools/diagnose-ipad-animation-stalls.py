#!/usr/bin/env python3
"""Opt-in, one-shot evidence collection around an unchanged XCTest command.

Usage: diagnose-ipad-animation-stalls.py --simulator UUID --output DIR -- xcodebuild ...
No simulator settings are changed. A captured idle wait is evidence, not a
diagnosis of an application deadlock. Python 3.9+; macOS sample, ps and xcrun.
"""

import argparse
import concurrent.futures
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
        if not self.arm_source:
            return None
        if WARNING in line:
            return self._fire("missing-animation-completion", now)
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
         on_line=None, env=None):
    """Run a bounded, owned collector, keeping output and nonfatal errors."""
    started = time.monotonic()
    result = {"command": command, "output": str(output), "exitCode": None}
    process = None
    pending = b""
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
            stop_owned_process(process)
            result["exitCode"] = process.returncode
            if process.returncode and not result.get("error") and not result.get("stopped"):
                result["error"] = "collector exited unsuccessfully"
    except (OSError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    finally:
        if process is not None:
            stop_owned_process(process)
            process.stdout.close()
        result["elapsedSeconds"] = round(time.monotonic() - started, 3)
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
    command = ["xcrun", "simctl", "spawn", args.simulator, "/bin/sh", "-c",
               'printf "SurroundAnimationCollectorPID=%s\\n" "$$"; export DYLD_ROOT_PATH="$SIMULATOR_ROOT"; exec "$SIMULATOR_ROOT/usr/bin/log" stream "$@"',
               "surround-animation-log", "--style", "compact", "--level", "debug",
               "--timeout", str(args.log_seconds), "--predicate", LOG_PREDICATE]
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
              "commandExitCode": None, "errors": []}
    detector = StallDetector(args.stall_seconds)
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
                    command.send_signal(signum)  # Exact wrapped PID, no process-group or runner signal.
                except ProcessLookupError:
                    pass

    def maybe_capture(trigger, pool):
        nonlocal capture_future
        if trigger and capture_future is None and not stop.is_set():
            status["trigger"] = trigger
            print("[SurroundAnimation] Capturing one early idle-wait diagnostic.", file=sys.stderr, flush=True)
            capture_future = pool.submit(capture, args, output, stop)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[signum] = signal.signal(signum, interrupted_by)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
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
                                    maybe_capture(detector.feed(line.decode("utf-8", errors="replace"), time.monotonic()), pool)
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
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        status["signal"] = interrupted
        code = status["commandExitCode"]
        status["exitCode"] = 128 + interrupted if interrupted else (128 - code if code is not None and code < 0 else code)
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
            and 1024 <= args.log_max_bytes <= 64 * 1024 * 1024):
        parser.error("Diagnostic limits out of bounds")
    try:
        return run(args)
    except FileExistsError:
        parser.error("--output already exists; choose a fresh directory")


if __name__ == "__main__":
    sys.exit(main())
