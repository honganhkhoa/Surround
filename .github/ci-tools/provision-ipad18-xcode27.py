#!/usr/bin/env python3
"""Provision the exact native-resize comparison device, or fail without fallback.

Only the optional hosted job calls this helper. Tests use fake tools, never a
local simulator. Apple documents build-number downloads and secure exports in:
https://developer.apple.com/documentation/xcode-release-notes/xcode-16_1-release-notes
https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes
"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


XCODE_VERSION = "27.1"
XCODE_BUILD = "27A9269"
RUNTIME_ID = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
RUNTIME_VERSION = "18.6"
RUNTIME_BUILD = "22G86"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB"
UUID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")


class ProvisioningError(Exception):
    pass


class Provisioner:
    def __init__(self, output, download_dir, timeout_seconds):
        self.output = output
        self.download_dir = download_dir
        self.started = time.monotonic()
        self.deadline = self.started + timeout_seconds
        self.metadata = {
            "outcome": "running", "sourceSHA": os.environ.get("GITHUB_SHA"),
            "runnerImage": os.environ.get("ImageVersion"),
            "runnerOS": os.environ.get("RUNNER_OS"),
            "runnerArchitecture": os.environ.get("RUNNER_ARCH"),
            "developerDirectoryEnvironment": os.environ.get("DEVELOPER_DIR"),
            "expected": {"xcodeVersion": XCODE_VERSION, "xcodeBuild": XCODE_BUILD,
                         "runtimeIdentifier": RUNTIME_ID, "runtimeVersion": RUNTIME_VERSION,
                         "runtimeBuild": RUNTIME_BUILD, "deviceTypeIdentifier": DEVICE_TYPE},
            "commands": [],
        }

    def save(self):
        self.metadata["elapsedSeconds"] = round(time.monotonic() - self.started, 3)
        (self.output / "provision.json").write_text(
            json.dumps(self.metadata, indent=2) + "\n")

    def run(self, label, command, timeout=30):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise ProvisioningError("Provisioning exceeded its total time budget.")
        log = self.output / f"command{len(self.metadata['commands']) + 1:02d}-{label}.log"
        stdout_log = log.with_suffix(".stdout")
        record = {"command": command, "log": log.name,
                  "stdoutLog": stdout_log.name, "stderrLog": log.name,
                  "timeoutSeconds": round(min(timeout, remaining), 3)}
        self.metadata["commands"].append(record)
        self.save()
        started = time.monotonic()
        # Machine output (JSON or the created UUID) must not include successful
        # commands' stderr warnings. Retain both streams in the uploaded evidence.
        with stdout_log.open("wb") as stdout_stream, log.open("wb") as stderr_stream:
            process = subprocess.Popen(command, stdout=stdout_stream, stderr=stderr_stream,
                                       start_new_session=True)
            try:
                record["exitCode"] = process.wait(timeout=min(timeout, remaining))
            except subprocess.TimeoutExpired:
                record["timedOut"] = True
                # Stop only this helper's command and descendants, including a
                # download/import child; never signal an app or test runner.
                grace_deadline = time.monotonic() + 2
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
                # The leader can exit while a descendant ignores TERM. Wait the
                # bounded grace, then escalate the owned group regardless of the
                # leader's exit status; an already absent group is harmless.
                grace_remaining = grace_deadline - time.monotonic()
                if grace_remaining > 0:
                    time.sleep(grace_remaining)
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=2)
                record["exitCode"] = process.returncode
                raise ProvisioningError(
                    f"{label} timed out; see {log.name} and {stdout_log.name}.")
            finally:
                record["elapsedSeconds"] = round(time.monotonic() - started, 3)
                self.save()
        if record["exitCode"] != 0:
            raise ProvisioningError(
                f"{label} failed with exit {record['exitCode']}; "
                f"see {log.name} and {stdout_log.name}. "
                "No other runtime or test route will be used.")
        return stdout_log.read_text(errors="replace")

    def query(self, label, kind):
        try:
            value = json.loads(self.run(label, ["xcrun", "simctl", "list", "--json", kind]))
        except json.JSONDecodeError as error:
            raise ProvisioningError(f"{label} returned invalid JSON.") from error
        if not isinstance(value, dict):
            raise ProvisioningError(f"{label} returned an invalid inventory.")
        return value

    def exact_runtime(self, inventory):
        runtimes = inventory.get("runtimes")
        if not isinstance(runtimes, list) or not all(isinstance(r, dict) for r in runtimes):
            raise ProvisioningError("Runtime inventory is missing its records.")
        matches = [r for r in runtimes if r.get("identifier") == RUNTIME_ID]
        if not matches:
            return None
        if len(matches) != 1:
            raise ProvisioningError("The exact iPadOS 18.6 runtime identifier is ambiguous.")
        runtime = matches[0]
        if (runtime.get("version") != RUNTIME_VERSION
                or runtime.get("buildversion") != RUNTIME_BUILD
                or runtime.get("isAvailable") is not True):
            raise ProvisioningError(
                "Installed iPadOS 18.6 must be available and exactly build 22G86; "
                "refusing a mismatched or unavailable runtime.")
        return runtime

    def provision(self):
        version = self.run("xcode-version", ["xcodebuild", "-version"])
        self.metadata["xcodeVersionOutput"] = version.strip()
        if version.splitlines() != [f"Xcode {XCODE_VERSION}", f"Build version {XCODE_BUILD}"]:
            raise ProvisioningError("Expected selected Xcode 27.1 build 27A9269.")
        self.metadata["developerDirectory"] = self.run(
            "developer-directory", ["xcode-select", "-p"]).strip()
        runtime = self.exact_runtime(self.query("runtimes-before", "runtimes"))
        if runtime is None:
            self.download_dir.mkdir(parents=True, exist_ok=False)
            self.run("first-launch", ["xcodebuild", "-runFirstLaunch"], timeout=120)
            self.run("download-ios18.6", [
                "xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", RUNTIME_BUILD,
                "-architectureVariant", "arm64", "-exportPath", str(self.download_dir),
            ], timeout=600)
            packages = [p for p in self.download_dir.iterdir() if not p.is_symlink() and (
                (p.is_file() and p.suffix == ".dmg") or
                (p.is_dir() and p.suffix in (".exportedBundle", ".exportBundle")))]
            if len(packages) != 1:
                raise ProvisioningError(
                    "Expected exactly one official runtime export package; "
                    "refusing missing or ambiguous downloads.")
            self.metadata["exportPackage"] = packages[0].name
            self.run("import-ios18.6", ["xcodebuild", "-importPlatform", str(packages[0])],
                     timeout=180)
            runtime = self.exact_runtime(self.query("runtimes-after", "runtimes"))
            if runtime is None:
                raise ProvisioningError("Import did not provide iPadOS 18.6 build 22G86.")
        self.metadata["runtime"] = runtime
        inventory = self.query("device-types", "devicetypes")
        types = inventory.get("devicetypes")
        if not isinstance(types, list) or not all(isinstance(t, dict) for t in types):
            raise ProvisioningError("Device-type inventory is missing its records.")
        matches = [t for t in types if t.get("identifier") == DEVICE_TYPE]
        if len(matches) != 1:
            raise ProvisioningError("The exact iPad Pro 11-inch (M4, 8GB) type is unavailable.")
        self.metadata["deviceType"] = matches[0]
        suffix = f"{os.environ.get('GITHUB_RUN_ID', 'manual')}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}"
        name = f"Surround-Xcode27-iPadOS18.6-M4-{suffix}"
        simulator_id = self.run("create-device", [
            "xcrun", "simctl", "create", name, DEVICE_TYPE, RUNTIME_ID]).strip()
        if not UUID.fullmatch(simulator_id):
            raise ProvisioningError("Device creation did not return exactly one simulator UUID.")
        self.metadata["createdSimulatorID"] = simulator_id
        self.save()  # Retain the owned UUID for the workflow's always-run cleanup.
        devices = self.query("devices-after", "devices").get("devices")
        if not isinstance(devices, dict):
            raise ProvisioningError("Device inventory is missing its records.")
        records = []
        for runtime_id, group in devices.items():
            if not isinstance(group, list) or not all(isinstance(d, dict) for d in group):
                raise ProvisioningError("Device inventory contains invalid records.")
            records += [(runtime_id, d) for d in group if d.get("udid") == simulator_id]
        if len(records) != 1:
            raise ProvisioningError("Created simulator is missing or ambiguous in the inventory.")
        runtime_id, device = records[0]
        if (runtime_id != RUNTIME_ID or device.get("deviceTypeIdentifier") != DEVICE_TYPE
                or device.get("isAvailable") is not True or device.get("name") != name):
            raise ProvisioningError("Created simulator failed exact runtime/model/availability checks.")
        self.metadata["device"] = device
        self.metadata["outcome"] = "success"
        self.save()
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
                stream.write(f"id={simulator_id}\n")
        print(f"Verified Xcode 27.1 / iPadOS 18.6 (22G86) / M4 8GB: {simulator_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download-dir", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=float, default=780)
    args = parser.parse_args()
    if not 0 < args.timeout_seconds <= 780:
        parser.error("timeout-seconds must be positive and at most 780")
    args.output.mkdir(parents=True, exist_ok=True)
    provisioner = Provisioner(args.output, args.download_dir, args.timeout_seconds)
    try:
        provisioner.provision()
    except (ProvisioningError, OSError, subprocess.SubprocessError) as error:
        provisioner.metadata.update(outcome="failure", error=str(error))
        provisioner.save()
        print(f"Exact iPadOS 18.6 provisioning failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
