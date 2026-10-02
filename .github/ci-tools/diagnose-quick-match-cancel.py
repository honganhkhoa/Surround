#!/usr/bin/env python3
"""Branch-only QuickMatch capture around the original focused XCTest command.

Reuse the bounded process/log collectors, with a QuickMatch-specific predicate
and a single Cancel-to-Find stall trigger. Do not change or retry test input.
"""

import argparse
import importlib.util
import json
from pathlib import Path
import re
import signal
import subprocess
import sys


spec = importlib.util.spec_from_file_location(
    "animation_collectors", Path(__file__).with_name("diagnose-ipad-animation-stalls.py")
)
collectors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collectors)


class QuickMatchStallDetector(collectors.StallDetector):
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.simulator):
        parser.error("Use an exact simulator UUID")
    if args.command and args.command[0] == "--":
        args.command.pop(0)
    if not args.command:
        parser.error("Supply the unchanged focused test command after --")

    args.stall_seconds = 5
    args.sample_seconds = 2
    args.capture_timeout = 10
    args.log_seconds = 1200
    args.log_max_bytes = 16 * 1024 * 1024
    output = Path(args.output).resolve()
    if output.exists():
        parser.error("Use a fresh capture output directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    video_path = output.parent / "QuickMatch-native.mp4"
    if video_path.exists():
        parser.error("Video path already exists; no evidence may be overwritten")
    collectors.StallDetector = QuickMatchStallDetector
    collectors.LOG_PREDICATE = (
        'category == "UIQuickMatchDiagnostics" OR '
        '((process == "Surround" OR process == "SurroundUITests-Runner" '
        'OR process == "testmanagerd") AND '
        '(eventMessage CONTAINS[c] "idle" OR eventMessage CONTAINS[c] "snapshot" '
        'OR eventMessage CONTAINS[c] "animation" OR eventMessage CONTAINS[c] "event"))'
    )

    video = None
    video_status = {"path": str(video_path), "errors": []}
    with open(output.parent / "QuickMatch-video.log", "wb", buffering=0) as video_log:
        try:
            video = subprocess.Popen(
                ["xcrun", "simctl", "io", args.simulator, "recordVideo", "--type=mp4", str(video_path)],
                stdout=video_log, stderr=subprocess.STDOUT, start_new_session=True,
            )
        except OSError as error:
            video_status["errors"].append(str(error))
        try:
            code = collectors.run(args)
        finally:
            if video is not None:
                if video.poll() is None:
                    try:
                        video.send_signal(signal.SIGINT)  # Flush only our recording.
                        video.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        video_status["errors"].append("Video flush timeout")
                        collectors.stop_owned_process(video)
                    except ProcessLookupError:
                        pass
                video_status["exitCode"] = video.returncode
            output.mkdir(parents=True, exist_ok=True)
            (output / "video-status.json").write_text(json.dumps(video_status, indent=2) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
