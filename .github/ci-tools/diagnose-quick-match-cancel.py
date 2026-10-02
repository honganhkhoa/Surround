#!/usr/bin/env python3
"""Branch-only QuickMatch capture around the original focused XCTest command.

Reuse the bounded process/log collectors, with a QuickMatch-specific predicate
and a single Cancel-to-Find stall trigger. Do not change or retry test input.
"""

import argparse
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time
import uuid


spec = importlib.util.spec_from_file_location(
    "animation_collectors", Path(__file__).with_name("diagnose-ipad-animation-stalls.py")
)
collectors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collectors)


class QuickMatchStallDetector(collectors.StallDetector):
    on_test_started = None

    def check(self, now):
        if not self.fired and self.wait_since is not None and now - self.wait_since >= self.seconds:
            return self._fire("quick-match-cancel-to-find-delay", now)
        return None

    def _fire(self, reason, now):
        trigger = super()._fire(reason, now)
        trigger["cancelToFindSeconds"] = trigger.pop("idleSeconds")
        return trigger

    def feed(self, line, now):
        if re.search(r"Test Case .+ started\.", line):
            self.test = line.strip()
            self.arm_source = None
            self.wait_since = None
            if self.on_test_started is not None:
                self.on_test_started(self.test)
        elif re.search(r"Test Case .+ (passed|failed|skipped|exceeded execution)", line):
            self.test = None
            self.wait_since = None
        if not self.test or self.fired:
            return None
        if "[SurroundQuickMatchTest] event=cancel.tapBegin " in line:
            self.arm_source = line.strip()
            self.wait_since = now
        if "[SurroundQuickMatchTest] event=findAgain.queryEnd " in line:
            self.wait_since = None
        if self.arm_source and collectors.WARNING in line:
            return self._fire("quick-match-missing-animation-completion", now)
        return self.check(now)


def owned_log_pid(simulator, owner):
    """Find only our native simulator logger; never retain ps environments."""
    inventory = subprocess.run(
        ["ps", "-axo", "pid=,comm="], capture_output=True, text=True, timeout=3
    )
    inventory.check_returncode()
    found = []
    for line in inventory.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if (len(fields) != 2 or not fields[0].isdigit()
                or not (fields[1] == "log" or fields[1].endswith("/usr/bin/log"))):
            continue
        pid = int(fields[0])
        if verifies_log_owner(pid, simulator, owner):
            found.append(pid)
    if len(found) > 1:
        raise RuntimeError("Multiple owned log processes; refusing to choose")
    return found[0] if found else None


def runner_identity(simulator, output, index, test):
    directory = output / ("runner-case-" + str(index))
    directory.mkdir()
    result = {"test": test, "simulator": simulator,
              "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    launchctl = collectors.tool(
        ["xcrun", "simctl", "spawn", simulator, "launchctl", "list"],
        directory / "launchctl.log", 10,
    )
    result["launchctl"] = launchctl
    if launchctl.get("exitCode") == 0 and not launchctl.get("error"):
        try:
            processes = collectors.simulator_pids((directory / "launchctl.log").read_text())
            result["processes"] = processes
            runner = processes.get("runner")
            if runner is not None:
                identity = subprocess.run(
                    ["ps", "-p", str(runner["pid"]), "-o", "pid=,lstart=,comm="],
                    capture_output=True, text=True, timeout=3,
                )
                identity.check_returncode()
                result["runnerProcessIdentity"] = identity.stdout.strip()
            else:
                result["error"] = "No exact simulator runner job"
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            result["error"] = str(error)
    (directory / "identity.json").write_text(json.dumps(result, indent=2) + "\n")


def verifies_log_owner(pid, simulator, owner):
    check = subprocess.run(
        ["ps", "eww", "-p", str(pid), "-o", "command="],
        capture_output=True, text=True, timeout=3,
    )
    return check.returncode == 0 and re.search(r"^(?:.*?/)?log stream(?:\s|$)", check.stdout.strip()) and all(
        re.search(r"(?:^|\s)" + name + "=" + re.escape(value) + r"(?:\s|$)", check.stdout, re.I)
        for name, value in (("SIMULATOR_UDID", simulator), ("SURROUND_QUICKMATCH_LOG_OWNER", owner))
    )


def quick_match_log_stream(args, output, stop):
    owner = uuid.uuid4().hex
    guest_pid = None
    discovery_errors = []

    def discover():
        nonlocal guest_pid
        deadline = time.monotonic() + min(60, args.log_seconds)
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                guest_pid = owned_log_pid(args.simulator, owner)
                if guest_pid is not None:
                    return
            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                discovery_errors.append(str(error))
                return
            stop.wait(0.2)

    environment = os.environ.copy()
    environment["SIMCTL_CHILD_SURROUND_QUICKMATCH_LOG_OWNER"] = owner
    watcher = threading.Thread(target=discover, name="quick-match-log-owner")
    watcher.start()
    try:
        # A bare name resolves the runtime's executable through the device PATH.
        # An absolute host /bin/sh is a macOS binary and cannot use this runtime's dyld root.
        command = ["xcrun", "simctl", "spawn", args.simulator, "log", "stream",
                   "--style", "compact", "--level", "debug", "--timeout", str(args.log_seconds),
                   "--predicate", collectors.LOG_PREDICATE]
        result = collectors.tool(command, output / "simulator.log", args.log_seconds + 5,
                                 stop, args.log_max_bytes, env=environment)
    finally:
        watcher.join(timeout=12)
    result["guestPID"] = guest_pid
    result["ownershipDiscoveryErrors"] = discovery_errors
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
    return result


def start_video(simulator, path, stream):
    return subprocess.Popen(
        ["xcrun", "simctl", "io", simulator, "recordVideo", "--codec=h264", str(path)],
        stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
    )


def await_video(process, log):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Recorder exited before readiness: " + str(process.returncode))
        if "Recording started" in log.read_text(errors="replace"):
            return {"recordingReadyAtEpoch": time.time(), "recordingReadyUptime": time.monotonic()}
        time.sleep(0.1)
    raise RuntimeError("Recorder did not report a first frame within 15 seconds")


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
        future = pool.submit(quick_match_log_stream, args, output, stop)
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
            ["xcrun", "swift", str(Path(__file__).with_name("verify-quick-match-video.swift")),
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
    if not args.command and not args.validate_collectors:
        parser.error("Supply the unchanged focused test command after --")

    args.stall_seconds = 5
    args.sample_seconds = 2
    args.capture_timeout = 10
    args.log_seconds = 2100
    args.log_max_bytes = 16 * 1024 * 1024
    output = Path(args.output).resolve()
    if output.exists():
        parser.error("Use a fresh capture output directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    video_path = output.parent / "QuickMatch-native.mp4"
    if video_path.exists():
        parser.error("Video path already exists; no evidence may be overwritten")
    collectors.StallDetector = QuickMatchStallDetector
    collectors.log_stream = quick_match_log_stream
    collectors.LOG_PREDICATE = (
        'category == "UIQuickMatchDiagnostics" OR '
        '((process == "Surround" OR process == "SurroundUITests-Runner" '
        'OR process == "testmanagerd") AND '
        '(eventMessage CONTAINS[c] "idle" OR eventMessage CONTAINS[c] "snapshot" '
        'OR eventMessage CONTAINS[c] "animation" OR eventMessage CONTAINS[c] "event"))'
    )

    if args.validate_collectors:
        return validate_collectors(args)

    runner_threads = []
    test_starts = []

    def capture_started_test(test):
        index = len(test_starts) + 1
        test_starts.append({"index": index, "test": test,
                            "observedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
        thread = threading.Thread(target=runner_identity,
                                  args=(args.simulator, output, index, test),
                                  name="quick-match-runner-" + str(index))
        runner_threads.append(thread)
        thread.start()

    QuickMatchStallDetector.on_test_started = staticmethod(capture_started_test)

    video = None
    video_status = {"path": str(video_path), "errors": []}
    with open(output.parent / "QuickMatch-video.log", "wb", buffering=0) as video_log:
        try:
            video = start_video(args.simulator, video_path, video_log)
            video_status.update(await_video(video, output.parent / "QuickMatch-video.log"))
        except (OSError, RuntimeError) as error:
            video_status["errors"].append(str(error))
        try:
            # Validate recorder readiness before starting the unchanged test command.
            code = collectors.run(args) if not video_status["errors"] else 1
        finally:
            for thread in runner_threads:
                thread.join(timeout=15)
            if video is not None:
                ended = finish_video(video, video_path)
                ended["errors"] = video_status["errors"] + ended["errors"]
                ended.update({key: value for key, value in video_status.items() if key.startswith("recordingReady")})
                video_status = ended
            output.mkdir(parents=True, exist_ok=True)
            (output / "test-starts.json").write_text(json.dumps(test_starts, indent=2) + "\n")
            (output / "video-status.json").write_text(json.dumps(video_status, indent=2) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
