#!/usr/bin/env python3
"""Run one CI UI-test step under a deadline and rerun only simulator-crash and query-timeout victims.

Usage: supervise-ipad-ui-test-part.py --simulator UUID --deadline-seconds 2760 \
    --diagnostics DIR -- xcodebuild test-without-building ... -resultBundlePath NAME.xcresult

At the deadline xcodebuild's process group receives SIGINT, then SIGTERM and
SIGKILL, so xcodebuild can still finish its result bundle inside the CI step
limit. When the first run fails, DIR keeps its console, the crash reports and
CoreSimulator.log lines written during it, and status.json with the rerun
decision; a failed rerun adds its own under a rerun- prefix. Tests are rerun
once, into NAME-Rerun.xcresult, only when every failure is either a test
crashed by SIGTERM or SIGKILL, or XCTest timing out while it evaluated a UI
query; neither the app nor its test runner left a crash report; and, for a
crash, a SimRenderServer crash report or CoreSimulator's rendering-service
recovery appeared during the run; for a query timeout, XCTest never reported
the app failing to go idle during that test. Before the rerun, the simulator must read
Booted and `simctl bootstatus` must report its boot finished. Python 3.9+;
macOS xcrun.
"""

import argparse
from collections import deque
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time


# The failure text XCTest records for the test that was running when the
# simulator rebooted underneath it.
CRASH_FAILURE = re.compile(r"Test crashed with signal (?:term|kill)\.?")
# The failure text XCTest records when one accessibility query outlasts its own
# timeout. On hosted runners such queries stall in episodes late in a job
# (October 2026) and fail whichever test is running. XCTest reports an app main
# thread it finds busy differently ("process main thread busy"), which is never
# rerun; a hang that only makes queries time out reads like a stall.
QUERY_TIMEOUT_FAILURE = re.compile(
    r"Failed to (?:get matching snapshots?|resolve query): Timed out while evaluating UI query\.?")
FAILED_TEST_CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' failed \((\d+(?:\.\d+)?) seconds\)")
STARTED_TEST_CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' started")
ENDED_TEST_CASE = re.compile(r"Test Case '-\[[^]]+\]' (?:passed|failed|skipped)")
WAIT_FOR_IDLE = re.compile(r"Wait for (\S+) to idle")
# XCTest's notes that a wait for the app to go idle gave up. In CI, the one
# query timeout that matched a hang (continuity, where another run of the same
# step failed with "process main thread busy") came right after such a note
# ended the app's last idle wait. None of ten stall timeouts did, although the
# note also appears in tests that recover, during stall episodes too. So only a
# note ending the app's latest idle wait counts. The composer phase's
# keyboard-animation stall prints the first note as well, so such a composer
# failure stays red.
APP_NOT_IDLE = ("App animations complete notification not received",
                "App event loop idle notification not received")
# About what xcodebuild spends around a part's tests: 36 s before the first and
# 64 s after the last until it reported the result, in CI run 40462251724's
# iPadOS 26 Messages part 2.
RERUN_OVERHEAD_SECONDS = 100
BOOT_LIMIT_SECONDS = 180
BOOT_POLL_SECONDS = 2
SIMULATOR_CRASH_PROCESS = "SimRenderServer"
TESTED_PROCESSES = ("Surround", "SurroundUITests-Runner")
TESTED_BUNDLES = ("com.honganhkhoa.Surround", "com.honganhkhoa.SurroundUITests.xctrunner")
CORE_SIMULATOR_RECOVERY = "com.apple.CoreSimulator.SimRenderingServices reported a critical error"
CONSOLE_MARKERS = {
    "runnerRestarts": "Restarting after unexpected exit, crash, or test timeout",
    "connectionInterruptions": "Connection interrupted",
    "executionTimeAllowanceFailures": "exceeded execution time allowance",
}
REPORT_DIRECTORIES = ("~/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports")
CORE_SIMULATOR_LOG = "~/Library/Logs/CoreSimulator/CoreSimulator.log"
REPORT_NAME = re.compile(r"(.+?)-\d{4}-\d\d-\d\d-\d{6}(?:[-.]\d+)?\.ips")
DEADLINE_EXIT_CODE = 124
MAX_RERUN_TESTS = 3
REPORT_COPY_LIMIT = 32 * 1024 * 1024
REPORT_READ_LIMIT = 4 * 1024 * 1024
# CI's CoreSimulator.log grows about 0.6 MB a minute, almost all of it one
# repeated device-identity error. The whole appended range is searched. The
# excerpt drops that error and keeps every recovery line, the first 1 MB of
# other rendering-service and device-state lines, and the last 4 MB of the rest.
LOG_NOISE = "Failed to get a device identity"
LOG_KEEP = ("SimRenderingServices", "current state:")
LOG_EXCERPT_LIMIT = 4 * 1024 * 1024
LOG_KEEP_LIMIT = 1024 * 1024
SELECTOR_OPTIONS = ("-only-testing", "-skip-testing")


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def annotate(level, title, message):
    """Print a GitHub Actions annotation; plain text elsewhere."""
    escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print("::{} title={}::{}".format(level, title, escaped), flush=True)


def result_bundle_of(command):
    paths = [command[index + 1] for index, value in enumerate(command[:-1])
             if value == "-resultBundlePath"]
    if len(paths) != 1 or command[-1] == "-resultBundlePath":
        raise ValueError("The test command needs exactly one -resultBundlePath")
    if not paths[0].endswith(".xcresult"):
        raise ValueError("The result bundle path must end in .xcresult")
    return paths[0]


def rerun_bundle_of(bundle):
    return bundle[:-len(".xcresult")] + "-Rerun.xcresult"


def rerun_command(command, tests, bundle):
    """The same xcodebuild invocation, narrowed to `tests`, writing `bundle`."""
    rewritten = []
    skip_value = False
    for value in command:
        if skip_value:
            skip_value = False
        elif value == "-resultBundlePath" or value in SELECTOR_OPTIONS:
            skip_value = True
        elif not value.startswith(tuple(option + ":" for option in SELECTOR_OPTIONS)):
            rewritten.append(value)
    return (rewritten + ["-only-testing:" + test for test in tests]
            + ["-resultBundlePath", bundle])


def read_summary(bundle, timeout=20):
    completed = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", bundle],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if completed.returncode:
        raise RuntimeError("xcresulttool exited {}: {}".format(
            completed.returncode, completed.stderr.decode("utf-8", "replace").strip()[:500]))
    return json.loads(completed.stdout)


def summarize_failures(summary):
    return [{"test": failure.get("testIdentifierString"), "target": failure.get("targetName"),
             "failure": (failure.get("failureText") or "")[:500]}
            for failure in summary.get("testFailures") or []]


def rerun_candidates(summary):
    """Return ({selector: causes}, None) when every failure is a signal crash or
    a UI query timeout, else (None, reason). A cause is "crash" or "queryTimeout"."""
    failures = summary.get("testFailures") or []
    if not failures:
        return None, "the result bundle records no test failure"
    tests = {}
    for failure in failures:
        target = failure.get("targetName")
        identifier = failure.get("testIdentifierString")
        text = (failure.get("failureText") or "").strip()
        if not target or not identifier:
            return None, "a failure has no test identifier"
        if CRASH_FAILURE.fullmatch(text):
            cause = "crash"
        elif QUERY_TIMEOUT_FAILURE.fullmatch(text):
            cause = "queryTimeout"
        else:
            return None, "{} failed with: {}".format(identifier, text[:200])
        tests.setdefault(target + "/" + re.sub(r"\(\)$", "", identifier), set()).add(cause)
    if summary.get("failedTests") != len(tests):
        return None, "{} failed tests but {} can be rerun".format(summary.get("failedTests"), len(tests))
    if len(tests) > MAX_RERUN_TESTS:
        return None, "{} tests failed, more than the {} a rerun takes".format(len(tests), MAX_RERUN_TESTS)
    return tests, None


def rerun_seconds(tests, durations, min_rerun):
    """The time a rerun of `tests` ({selector: causes}) needs before the deadline.

    A query-timeout rerun needs xcodebuild's overhead plus the time each test
    ran in the first attempt, until it failed. A long journey that failed early
    can take longer to pass; the deadline then stops the rerun, and the step
    fails as it would have without one. A crash rerun follows a reboot, and a
    crashed test's duration is cut short, so a rerun with a crash or an unknown
    duration needs at least `min_rerun`.
    """
    timed_out = [test for test, causes in tests.items() if "crash" not in causes]
    needed = RERUN_OVERHEAD_SECONDS + sum(durations.get(test, 0) for test in timed_out) if timed_out else 0
    if len(timed_out) < len(tests) or any(test not in durations for test in timed_out):
        needed = max(needed, min_rerun)
    return needed


def report_snapshot(directories):
    found = {}
    for directory in directories:
        try:
            entries = list(os.scandir(directory))
        except OSError:
            continue
        for entry in entries:
            try:
                if entry.name.endswith(".ips") and entry.is_file():
                    found[entry.path] = entry.stat().st_mtime
            except OSError:
                pass  # Renamed or pruned while the directory was read.
    return found


def new_reports(directories, before, started_at):
    return sorted(path for path, modified in report_snapshot(directories).items()
                  if before.get(path) != modified and modified >= started_at - 1)


def describe_report(path):
    """Process, bundle and crash reason of an .ips report; never raises."""
    described = {"path": path, "process": None, "bundleID": None, "exception": None, "reason": None}
    try:
        with open(path, "rb") as stream:
            header = json.loads(stream.readline(65536))
            described["process"] = header.get("app_name") or header.get("name")
            described["bundleID"] = header.get("bundleID")
            body = json.loads(stream.read(REPORT_READ_LIMIT))
        exception = body.get("exception") or {}
        described["exception"] = " ".join(filter(None, (exception.get("type"), exception.get("signal")))) or None
        reasons = [text for values in (body.get("asi") or {}).values() for text in values]
        described["reason"] = "; ".join(reasons[:2])[:300] or None
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    if not described["process"]:
        match = REPORT_NAME.fullmatch(Path(path).name)
        described["process"] = match.group(1) if match else Path(path).name
    return described


def is_tested_process(report):
    return report["process"] in TESTED_PROCESSES or report["bundleID"] in TESTED_BUNDLES


def log_position(path):
    try:
        status = os.stat(path)
        return status.st_ino, status.st_size
    except OSError:
        return None


def scan_core_simulator_log(path, start):
    """Search everything appended to the log since `start`, line by line.

    Returns (recovered, excerpt in log order, counts). After a rotation the new
    file is read from its start.
    """
    counts = {"noiseLinesOmitted": 0, "linesOverLimit": 0}
    now = log_position(path)
    if now is None:
        return False, "", counts
    offset = start[1] if start is not None and start[0] == now[0] and start[1] <= now[1] else 0
    recovered = False
    kept, kept_bytes = [], 0
    recent, recent_bytes = deque(), 0
    with open(path, "rb") as stream:
        stream.seek(offset)
        for number, raw in enumerate(stream):
            line = raw.decode("utf-8", errors="replace")
            if CORE_SIMULATOR_RECOVERY in line:
                recovered = True
                kept.append((number, line))
            elif any(marker in line for marker in LOG_KEEP):
                if kept_bytes + len(raw) <= LOG_KEEP_LIMIT:
                    kept.append((number, line))
                    kept_bytes += len(raw)
                else:
                    counts["linesOverLimit"] += 1
            elif LOG_NOISE in line:
                counts["noiseLinesOmitted"] += 1
            else:
                recent.append((number, line, len(raw)))
                recent_bytes += len(raw)
                while recent_bytes > LOG_EXCERPT_LIMIT:
                    recent_bytes -= recent.popleft()[2]
                    counts["linesOverLimit"] += 1
    lines = sorted(kept + [(number, line) for number, line, _ in recent])
    return recovered, "".join(line for _, line in lines), counts


def vm_uptime_seconds():
    try:
        boot = subprocess.run(["sysctl", "-n", "kern.boottime"], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=5).stdout.decode()
        return round(time.time() - int(re.search(r"sec = (\d+)", boot).group(1)))
    except (OSError, subprocess.SubprocessError, AttributeError, ValueError):
        return None


def rerun_decision(attempt, summary, summary_error, reports, recovered, remaining, min_rerun):
    """Return (tests, None) to rerun, or (None, reason). Never reruns an assertion."""
    if attempt["externalSignal"]:
        return None, "the step was interrupted"
    if attempt["stoppedAtDeadline"]:
        return None, "the step reached its deadline"
    if summary is None:
        return None, "the result bundle could not be read: " + (summary_error or "unknown error")
    tests, reason = rerun_candidates(summary)
    if reason:
        return None, reason
    if attempt["consoleMarkers"].get("executionTimeAllowanceFailures"):
        return None, "a test exceeded its execution time allowance"
    tested = sorted({report["process"] for report in reports if is_tested_process(report)})
    if tested:
        return None, "a crash report names the tested process " + ", ".join(tested)
    if (any("crash" in causes for causes in tests.values()) and not recovered
            and not any(report["process"] == SIMULATOR_CRASH_PROCESS for report in reports)):
        return None, "no SimRenderServer crash report or rendering-service recovery appeared"
    not_idle = attempt.get("appNotIdle") or {}
    for test in sorted(tests):
        if "queryTimeout" in tests[test] and test in not_idle:
            return None, "the app did not go idle before {} failed (\"{}\"), so its query timeout may be a hang".format(
                test, not_idle[test])
    needed = rerun_seconds(tests, attempt.get("failedTestSeconds") or {}, min_rerun)
    if remaining < needed:
        return None, "only {:.0f} s remain before the deadline, and the rerun needs {:.0f} s".format(
            max(0, remaining), needed)
    return sorted(tests), None


class Supervisor:
    def __init__(self, args):
        self.args = args
        self.started = time.monotonic()
        self.deadline = self.started + args.deadline_seconds
        self.external_signals = []

    def remaining(self):
        return self.deadline - time.monotonic()

    def on_signal(self, signum, _frame):
        # The run loop turns each one into the next stop stage.
        self.external_signals.append(signum)

    def screenshot(self, path):
        def capture():
            try:
                subprocess.run(["xcrun", "simctl", "io", self.args.simulator, "screenshot", str(path)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            except (OSError, subprocess.SubprocessError):
                pass
        thread = threading.Thread(target=capture, daemon=True)
        thread.start()
        return thread

    def run(self, command, console_path, screenshot_path):
        """Run one xcodebuild, mirroring its output; stop it at the shared deadline."""
        result = {"command": command, "exitCode": None, "stoppedAtDeadline": False,
                  "signalsSent": [], "externalSignal": None,
                  "consoleMarkers": dict.fromkeys(CONSOLE_MARKERS, 0), "failedTestSeconds": {},
                  "appNotIdle": {}}
        started = time.monotonic()
        if self.external_signals:
            result["externalSignal"] = self.external_signals[0]
            return result
        pending = b""
        stage, stage_started, exited_at = 0, None, None
        handled_signals = 0
        stdout_held = False
        capture = None
        current_test = idle_wait = None
        mirror = True
        with open(console_path, "wb", buffering=0) as console:
            child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     bufsize=0, start_new_session=True)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(child.stdout, selectors.EVENT_READ)
                    while selector.get_map() or child.poll() is None:
                        now = time.monotonic()
                        if child.poll() is not None:
                            if exited_at is None:
                                exited_at = now
                            elif now - exited_at >= 2:
                                stdout_held = True  # A descendant outlived xcodebuild.
                                break
                        elif len(self.external_signals) > handled_signals and stage < 3:
                            handled_signals += 1
                            stage, stage_started = self.stop(child, stage + 1, result), now
                        elif stage == 0 and now >= self.deadline:
                            result["stoppedAtDeadline"] = True
                            print("\n[SurroundCI] The {:.0f}-minute deadline passed; interrupting xcodebuild so it "
                                  "can write its result bundle.".format(self.args.deadline_seconds / 60),
                                  file=sys.stderr, flush=True)
                            capture = self.screenshot(screenshot_path)
                            stage, stage_started = self.stop(child, 1, result), now
                        elif stage == 1 and now - stage_started >= self.args.interrupt_grace_seconds:
                            stage, stage_started = self.stop(child, 2, result), now
                        elif stage == 2 and now - stage_started >= self.args.terminate_grace_seconds:
                            stage, stage_started = self.stop(child, 3, result), now
                        for key, _ in selector.select(0.1):
                            data = os.read(key.fd, 65536)
                            if not data:
                                selector.unregister(key.fileobj)
                                continue
                            console.write(data)
                            if mirror:
                                try:
                                    sys.stdout.buffer.write(data)
                                    sys.stdout.buffer.flush()
                                except BrokenPipeError:
                                    mirror = False
                            pending += data
                            while b"\n" in pending:
                                line, pending = pending.split(b"\n", 1)
                                text = line.decode("utf-8", errors="replace")
                                for name, marker in CONSOLE_MARKERS.items():
                                    if marker in text:
                                        result["consoleMarkers"][name] += 1
                                test_started = STARTED_TEST_CASE.search(text)
                                if test_started:
                                    current_test, idle_wait = "/".join(test_started.group(1, 2, 3)), None
                                wait = WAIT_FOR_IDLE.search(text)
                                if wait:
                                    idle_wait = wait.group(1)
                                    if idle_wait == TESTED_BUNDLES[0] and current_test:
                                        result["appNotIdle"].pop(current_test, None)
                                marker = next((marker for marker in APP_NOT_IDLE if marker in text), None)
                                if marker and current_test and idle_wait == TESTED_BUNDLES[0]:
                                    result["appNotIdle"][current_test] = marker
                                failed = FAILED_TEST_CASE.search(text)
                                if failed:
                                    result["failedTestSeconds"]["/".join(failed.group(1, 2, 3))] = float(
                                        failed.group(4))
                                if ENDED_TEST_CASE.search(text):
                                    current_test = None
                            pending = pending[-1024 * 1024:]
            finally:
                if child.poll() is None:  # Only an exception can leave the loop early.
                    self.stop(child, 3, result)
                    child.wait()
                if stage or stdout_held:
                    # Nothing in xcodebuild's group outlives a stop or a held stdout.
                    self.kill_group(child.pid)
                child.stdout.close()
        if capture is not None:
            capture.join(timeout=20)
        code = child.returncode
        result["exitCode"] = 128 - code if code is not None and code < 0 else code
        if self.external_signals:
            result["externalSignal"] = self.external_signals[0]
        result["elapsedSeconds"] = round(time.monotonic() - started, 1)
        return result

    def stop(self, child, stage, result):
        """Escalate SIGINT, SIGTERM, then SIGKILL to xcodebuild's process group.

        Signal the group as Ctrl-C would. Interrupted alone mid-test, xcodebuild
        waited on its app-launch workers and never wrote Info.plist; with its
        group interrupted it saved a readable bundle within a minute.
        """
        signum = {1: signal.SIGINT, 2: signal.SIGTERM, 3: signal.SIGKILL}[stage]
        try:
            os.killpg(child.pid, signum)
            result["signalsSent"].append(signal.Signals(signum).name)
        except (ProcessLookupError, PermissionError):
            pass  # The group is gone, or holds only an exited xcodebuild.
        return stage

    @staticmethod
    def kill_group(pgid):
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def bounded_tool(command, output, timeout):
    try:
        with open(output, "wb") as stream:
            completed = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        return {"command": command, "exitCode": completed.returncode}
    except (OSError, subprocess.SubprocessError) as error:
        return {"command": command, "error": str(error)}


def simulator_state(simulator):
    """simctl's state for the device, such as Booted or Shutdown, or None when unknown."""
    try:
        completed = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
        for devices in (json.loads(completed.stdout).get("devices") or {}).values():
            for device in devices:
                if str(device.get("udid", "")).upper() == simulator.upper():
                    return device.get("state")
    except (OSError, subprocess.SubprocessError, ValueError, AttributeError, TypeError):
        pass
    return None


def run_until(command, log, limit, stopped):
    """Run `command` into `log` for at most `limit` seconds, or until `stopped()`; never raises."""
    started = time.monotonic()
    log.flush()
    try:
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    except OSError as error:
        return {"command": command, "error": str(error)}
    while child.poll() is None:
        if stopped():
            reason = "interrupted"
        elif time.monotonic() - started >= limit:
            reason = "timed out after {:.0f} s".format(limit)
        else:
            time.sleep(0.2)
            continue
        child.kill()
        child.wait()
        return {"command": command, "error": reason}
    return {"command": command, "exitCode": child.returncode}


def boot_simulator(simulator, limit, log_path, stopped=lambda: False):
    """Wait up to `limit` seconds for the device to finish booting, booting it once if Shutdown.

    xcodebuild leaves a simulator that crashed Shutting Down, then Shutdown, so
    simctl's state settles first. Reading Booted is not enough: after a
    SimRenderServer crash on iPadOS 26.5, a rerun started as soon as the state
    read Booted had its test runner refused about 18 s later ("Busy",
    "Application failed preflight checks"). So `simctl bootstatus` then waits
    for the boot to finish. On CI (36aa3e5, October 2026) bootstatus stayed at
    "Waiting on System App" past a fixed 180 s; such a rerun is still refused,
    but within the time it can spare. `stopped` ends the wait early, for an
    outside signal.
    """
    started = time.monotonic()
    result = {"booted": False, "finished": False, "states": [], "boot": None, "bootStatus": None,
              "limitSeconds": round(limit, 1)}
    with open(log_path, "a") as log:  # simctl appends its own output.
        while True:
            state = simulator_state(simulator)
            elapsed = time.monotonic() - started
            log.write("{:.1f} s: {}\n".format(elapsed, state or "unknown"))
            log.flush()
            if not result["states"] or result["states"][-1] != state:
                result["states"].append(state)
            if state == "Booted":
                result["booted"] = True
                break
            if stopped():
                break
            if state == "Shutdown" and result["boot"] is None:
                result["boot"] = run_until(["xcrun", "simctl", "boot", simulator], log,
                                           max(1, limit - elapsed), stopped)
                continue
            if elapsed >= limit or (state == "Shutdown" and result["boot"].get("exitCode") != 0):
                break
            time.sleep(min(BOOT_POLL_SECONDS, limit - elapsed))
        if result["booted"] and not stopped():
            result["bootStatus"] = run_until(["xcrun", "simctl", "bootstatus", simulator], log,
                                             max(1, limit - (time.monotonic() - started)), stopped)
            result["finished"] = result["bootStatus"].get("exitCode") == 0
    result["elapsedSeconds"] = round(time.monotonic() - started, 1)
    return result


def boot_failure(boot):
    """Why the boot gate did not let a rerun start, naming its time limit when that ran out."""
    limit = "{:.0f} s".format(max(0, boot["limitSeconds"]))
    if boot["limitSeconds"] < BOOT_LIMIT_SECONDS:
        limit += ", all the time the rerun could spare"

    def failed(result, tool, timed_out):
        if "exitCode" in result:
            return "simctl {} exited {}".format(tool, result["exitCode"])
        if result["error"].startswith("timed out"):
            return timed_out + " within " + limit
        return "simctl {} failed: {}".format(tool, result["error"])

    if boot["booted"]:
        return "the simulator read Booted, but " + failed(
            boot["bootStatus"] or {"error": "not checked"}, "bootstatus",
            "simctl bootstatus did not report the boot finished")
    if boot["boot"] and boot["boot"].get("exitCode") != 0 and boot["states"][-1] == "Shutdown":
        detail = failed(boot["boot"], "boot", "simctl boot did not finish")
    else:
        detail = "it was still {} after {}".format(boot["states"][-1] or "in an unknown state", limit)
    return "the simulator did not boot again: " + detail


def copy_reports(paths, destination):
    """Describe every new report; copy them until REPORT_COPY_LIMIT is reached."""
    reports, total = [], 0
    for path in paths:
        report = describe_report(path)
        try:
            size = os.path.getsize(path)
            report["copied"] = total + size <= REPORT_COPY_LIMIT
            if report["copied"]:
                destination.mkdir(exist_ok=True)
                shutil.copy2(path, destination / Path(path).name)
                total += size
        except OSError as error:
            report["copied"] = False
            report["error"] = str(error)
        reports.append(report)
    return reports


def crash_summary(reports):
    for report in reports:
        if report["process"] == SIMULATOR_CRASH_PROCESS:
            details = ", ".join(filter(None, (report["exception"], report["reason"])))
            return "SimRenderServer crashed" + (" ({})".format(details) if details else "")
    return "CoreSimulator recovered its rendering service"


def cause_summary(causes, reports):
    parts = ([crash_summary(reports)] if "crash" in causes else []) + (
        ["a UI query timed out"] if "queryTimeout" in causes else [])
    summary = " and ".join(parts)
    return summary[:1].upper() + summary[1:]


def collect_crash_evidence(args, report_dirs, since, output, prefix, status):
    """Copy the reports and CoreSimulator.log lines written since `since`.

    `since` is (report snapshot, wall-clock start, log position); returns the
    reports and whether CoreSimulator recovered its rendering service.
    """
    reports_before, started_at, log_start = since
    reports = copy_reports(new_reports(report_dirs, reports_before, started_at),
                           output / (prefix + "DiagnosticReports"))
    recovered, counts = False, None
    try:
        recovered, excerpt, counts = scan_core_simulator_log(args.core_simulator_log, log_start)
        (output / (prefix + "CoreSimulator.log")).write_text(excerpt)
    except OSError as error:
        status["errors"].append(prefix + "CoreSimulator.log: " + str(error))
    return reports, recovered, counts


def evidence_start(report_dirs, core_simulator_log):
    return report_snapshot(report_dirs), time.time(), log_position(core_simulator_log)


def collect_failure(supervisor, args, bundle, attempt, console_temp, report_dirs, since, status):
    """Keep the failed first attempt's evidence.

    Returns (tests to rerun, their causes, the seconds the rerun needs), or
    three Nones.
    """
    output = Path(args.diagnostics)
    output.mkdir(parents=True)
    shutil.move(console_temp, str(output / "console.log"))
    summary, summary_error = None, None
    if Path(bundle).exists():
        try:
            summary = read_summary(bundle)
            attempt["failures"] = summarize_failures(summary)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            summary_error = str(error)
    else:
        summary_error = "no result bundle at " + bundle
    reports, recovered, status["coreSimulatorLog"] = collect_crash_evidence(
        args, report_dirs, since, output, "", status)
    status["simulatorDevices"] = bounded_tool(
        ["xcrun", "simctl", "list", "devices", "--json"], output / "simctl-devices.json", 15)
    status["crashReports"] = reports
    status["coreSimulatorRecovery"] = recovered
    remaining = supervisor.remaining()
    tests, reason = rerun_decision(attempt, summary, summary_error, reports, recovered,
                                   remaining, args.min_rerun_seconds)
    status["rerun"] = {"tests": tests, "reasonNotRerun": reason,
                       "remainingSecondsAtDecision": round(remaining)}
    status["crashSummary"] = status["causeSummary"] = None
    if not tests:
        return None, None, None
    candidates = rerun_candidates(summary)[0]
    causes = sorted(set().union(*candidates.values()))
    needed = rerun_seconds(candidates, attempt["failedTestSeconds"], args.min_rerun_seconds)
    status["rerun"].update(causes=causes, neededSeconds=round(needed))
    if "crash" in causes:
        status["crashSummary"] = crash_summary(reports)
    status["causeSummary"] = cause_summary(causes, reports)
    return tests, causes, needed


def run(args):
    command = args.command
    bundle = result_bundle_of(command)
    rerun_bundle = rerun_bundle_of(bundle)
    output = Path(args.diagnostics)
    report_dirs = [os.path.expanduser(directory) for directory in args.report_directory]
    args.core_simulator_log = os.path.expanduser(args.core_simulator_log)
    supervisor = Supervisor(args)
    status = {"simulator": args.simulator, "resultBundle": bundle, "startedAtUTC": utc_now(),
              "deadlineSeconds": args.deadline_seconds, "vmUptimeAtStartSeconds": vm_uptime_seconds(),
              "attempts": [], "errors": []}
    since = evidence_start(report_dirs, args.core_simulator_log)
    handlers = {signum: signal.signal(signum, supervisor.on_signal)
                for signum in (signal.SIGINT, signal.SIGTERM)}
    descriptor, console_temp = tempfile.mkstemp(prefix=".console-", suffix=".log",
                                                dir=str(output.parent))
    os.close(descriptor)
    deadline_shot = output.parent / (output.name + "-deadline.png")

    def interrupted():
        # An outside signal wins over every other outcome, as Ctrl-C would.
        if supervisor.external_signals:
            status["exitCode"] = 128 + supervisor.external_signals[0]
            if status.get("rerun") and status["rerun"].get("reasonNotRerun") is None:
                status["rerun"]["reasonNotRerun"] = "the step was interrupted"
            return True
        return False

    try:
        attempt = supervisor.run(command, console_temp, deadline_shot)
        status["attempts"].append(attempt)
        if attempt["exitCode"] == 0 and not attempt["stoppedAtDeadline"] and not supervisor.external_signals:
            return 0
        tests, causes, needed = collect_failure(supervisor, args, bundle, attempt, console_temp,
                                                report_dirs, since, status)
        if deadline_shot.exists():
            shutil.move(str(deadline_shot), str(output / "deadline.png"))
        if interrupted():
            return status["exitCode"]
        if attempt["stoppedAtDeadline"]:
            annotate("error", "UI-test deadline",
                     "xcodebuild was interrupted after {:.0f} minutes; see {}.".format(
                         args.deadline_seconds / 60, output))
            status["exitCode"] = DEADLINE_EXIT_CODE
            return DEADLINE_EXIT_CODE
        if not tests:
            print("[SurroundCI] No rerun: {}.".format(status["rerun"]["reasonNotRerun"]),
                  file=sys.stderr, flush=True)
            status["exitCode"] = attempt["exitCode"] or 1
            return status["exitCode"]
        names = ", ".join(tests)
        title = "Simulator crash" if "crash" in causes else "UI query timeout"
        print("[SurroundCI] {} during {}; rerunning only {} into {}.".format(
            status["causeSummary"], names, "it" if len(tests) == 1 else "them", rerun_bundle),
            file=sys.stderr, flush=True)
        boot = boot_simulator(args.simulator, min(BOOT_LIMIT_SECONDS, supervisor.remaining() - needed),
                              output / "boot.log", lambda: bool(supervisor.external_signals))
        status["rerun"]["boot"] = boot
        if interrupted():
            return status["exitCode"]
        refusal = None
        if not boot["finished"]:
            refusal = boot_failure(boot)
        elif supervisor.remaining() < needed:
            refusal = "only {:.0f} s remained after the simulator booted, and the rerun needs {:.0f} s".format(
                max(0, supervisor.remaining()), needed)
        if refusal:
            status["rerun"]["reasonNotRerun"] = refusal
            annotate("error", title, "No rerun of {}: {}.".format(names, refusal))
            status["exitCode"] = attempt["exitCode"] or 1
            return status["exitCode"]
        rerun_since = evidence_start(report_dirs, args.core_simulator_log)
        rerun = supervisor.run(rerun_command(command, tests, rerun_bundle), output / "rerun-console.log",
                               output / "rerun-deadline.png")
        status["attempts"].append(rerun)
        rerun_summary = None
        try:
            rerun_summary = read_summary(rerun_bundle)
            rerun["failures"] = summarize_failures(rerun_summary)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            status["errors"].append("rerun result bundle: " + str(error))
        # xcodebuild exits 0 when a selector matches nothing; require the tests ran.
        if (rerun["exitCode"] == 0 and not rerun["stoppedAtDeadline"] and not supervisor.external_signals
                and rerun_summary is not None and rerun_summary.get("failedTests") == 0
                and (rerun_summary.get("passedTests") or 0) >= len(tests)):
            annotate("warning", title + " recovered",
                     "{} during {}; it passed on a rerun. The first result bundle keeps the failure; "
                     "evidence is in {}.".format(status["causeSummary"], names, output))
            status["exitCode"] = 0
            return 0
        rerun_reports, rerun_recovered, rerun_log = collect_crash_evidence(
            args, report_dirs, rerun_since, output, "rerun-", status)
        status["rerun"].update(crashReports=rerun_reports, coreSimulatorRecovery=rerun_recovered,
                               coreSimulatorLog=rerun_log)
        if interrupted():
            return status["exitCode"]
        if rerun["stoppedAtDeadline"]:
            annotate("error", "UI-test deadline", "The deadline stopped the rerun of {}; see {}.".format(
                names, rerun_bundle))
            status["exitCode"] = DEADLINE_EXIT_CODE
        else:
            annotate("error", title, "The rerun of {} after {} did not pass; see {}.".format(
                names, "a simulator crash" if "crash" in causes else "a UI query timeout", rerun_bundle))
            status["exitCode"] = rerun["exitCode"] or attempt["exitCode"] or 1
        return status["exitCode"]
    finally:
        for signum, handler in handlers.items():
            signal.signal(signum, handler)
        for leftover in (console_temp, str(deadline_shot)):
            if os.path.exists(leftover):
                os.unlink(leftover)
        if output.exists():
            status["vmUptimeAtEndSeconds"] = vm_uptime_seconds()
            status["finishedAtUTC"] = utc_now()
            (output / "status.json").write_text(json.dumps(status, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--deadline-seconds", type=float, required=True)
    parser.add_argument("--diagnostics", required=True, help="Fresh directory, written only on failure")
    parser.add_argument("--min-rerun-seconds", type=float, default=300,
                        help="Seconds a crash rerun, or one without measured test durations, needs at least")
    parser.add_argument("--interrupt-grace-seconds", type=float, default=90)
    parser.add_argument("--terminate-grace-seconds", type=float, default=15)
    parser.add_argument("--report-directory", action="append", default=None)
    parser.add_argument("--core-simulator-log", default=CORE_SIMULATOR_LOG)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.simulator):
        parser.error("--simulator must be an exact UUID, never 'booted'")
    if args.command and args.command[0] == "--":
        args.command.pop(0)
    if not args.command:
        parser.error("Supply the xcodebuild command after --")
    if not (0 < args.deadline_seconds <= 6 * 3600 and 0 <= args.min_rerun_seconds <= 3600
            and 0 < args.interrupt_grace_seconds <= 600 and 0 < args.terminate_grace_seconds <= 120):
        parser.error("Time limits out of bounds")
    args.report_directory = args.report_directory or list(REPORT_DIRECTORIES)
    try:
        result_bundle_of(args.command)
    except ValueError as error:
        parser.error(str(error))
    if os.path.lexists(args.diagnostics):
        parser.error("--diagnostics already exists; choose a fresh directory")
    if not Path(args.diagnostics).parent.is_dir():
        parser.error("The parent of --diagnostics must exist")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
