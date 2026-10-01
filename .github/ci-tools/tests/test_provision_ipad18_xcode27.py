#!/usr/bin/env python3
"""Provisioning integration tests use fake tools only, never native simulators."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "provision-ipad18-xcode27.py"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB"
UDID = "11111111-2222-3333-4444-555555555555"

FAKE_TOOL = r'''
import json, os, pathlib, signal, subprocess, sys, time
root = pathlib.Path(os.environ["FAKE_ROOT"])
config = json.loads((root / "config.json").read_text())
tool, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps([tool] + args) + "\n")
time.sleep(config.get("commandDelay", 0))
runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
device_type = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB"
udid = "11111111-2222-3333-4444-555555555555"
if tool == "xcodebuild" and args == ["-version"]:
    print(config.get("toolchain", "Xcode 27.1\nBuild version 27A9269"))
elif tool == "xcode-select" and args == ["-p"]:
    print("/Applications/Xcode_27.1.app/Contents/Developer")
elif tool == "xcodebuild" and args == ["-runFirstLaunch"]:
    print("synthetic first launch")
elif tool == "xcodebuild" and args[:2] == ["-downloadPlatform", "iOS"]:
    if config.get("downloadFailure"):
        print("synthetic catalog failure")
        sys.exit(17)
    if config.get("downloadHang"):
        time.sleep(4)
    if config.get("downloadChild"):
        child_source = """
import os, pathlib, signal, sys, time
root = pathlib.Path(sys.argv[1])
signal.signal(signal.SIGTERM, lambda *_: (root / 'child-term-seen').write_text('ignored'))
(root / 'download-child.pid').write_text(str(os.getpid()))
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    (root / 'child-heartbeat').write_text(str(time.monotonic()))
    time.sleep(.02)
"""
        def exit_leader(*_):
            (root / "leader-term-exit").write_text("exited promptly")
            sys.exit(0)
        signal.signal(signal.SIGTERM, exit_leader)
        subprocess.Popen([sys.executable, "-c", child_source, str(root)])
        ready_by = time.monotonic() + 1
        while not (root / "download-child.pid").exists() and time.monotonic() < ready_by:
            time.sleep(.01)
        time.sleep(4)
    destination = pathlib.Path(args[args.index("-exportPath") + 1])
    destination.mkdir(parents=True, exist_ok=True)
    package = config.get("package", ".dmg")
    extensions = [".dmg", ".exportedBundle"] if package == "multiple" else [package]
    for extension in extensions:
        if extension == "none":
            continue
        path = destination / ("iOS 18.6 Runtime" + extension)
        if extension == ".dmg":
            path.write_bytes(b"synthetic disk image")
        else:
            path.mkdir()
            (path / "payload.dmg").write_bytes(b"nested payload must not be imported")
    print("synthetic download complete")
elif tool == "xcodebuild" and len(args) == 2 and args[0] == "-importPlatform":
    (root / "imported").write_text(args[1])
    print("synthetic import complete")
elif tool == "xcrun" and args == ["simctl", "list", "--json", "runtimes"]:
    mode = config.get("postRuntime", "exact") if (root / "imported").exists() else config.get("runtime", "exact")
    if mode == "malformed":
        print("not JSON")
    else:
        record = dict(identifier=runtime_id, version="18.6", buildversion="22G86", isAvailable=True, name="iOS 18.6")
        if mode == "wrongBuild": record["buildversion"] = "22G85"
        if mode == "wrongVersion": record["version"] = "18.5"
        if mode == "unavailable": record["isAvailable"] = False
        if mode == "availabilityNumber": record["isAvailable"] = 1
        if mode == "missingFields": record.pop("buildversion")
        records = [] if mode == "missing" else [record]
        if mode == "duplicate": records.append(dict(record))
        print(json.dumps({"runtimes": records}))
elif tool == "xcrun" and args == ["simctl", "list", "--json", "devicetypes"]:
    records = [] if config.get("missingType") else [dict(identifier=device_type, name="iPad Pro 11-inch (M4)")]
    print(json.dumps({"devicetypes": records}))
elif tool == "xcrun" and args[:2] == ["simctl", "create"]:
    (root / "created-name").write_text(args[2])
    if config.get("createWarning"):
        print(config["createWarning"], file=sys.stderr, flush=True)
    print(config.get("createOutput", udid))
elif tool == "xcrun" and args == ["simctl", "list", "--json", "devices"]:
    mode = config.get("device", "exact")
    record = dict(udid=udid, name=(root / "created-name").read_text(), deviceTypeIdentifier=device_type, isAvailable=True, state="Shutdown")
    if mode == "wrongType": record["deviceTypeIdentifier"] = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
    if mode == "unavailable": record["isAvailable"] = False
    records = [] if mode == "missing" else [record]
    if mode == "duplicate": records.append(dict(record))
    key = "com.apple.CoreSimulator.SimRuntime.iOS-27-0" if mode == "wrongRuntime" else runtime_id
    print(json.dumps({"devices": {key: records}}))
else:
    print("unexpected fake invocation", [tool] + args)
    sys.exit(99)
'''


class ProvisioningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / "evidence"
        self.download = self.root / "downloads"
        self.github_output = self.root / "github-output"
        self.github_output.write_text("")
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        for name in ("xcodebuild", "xcrun", "xcode-select"):
            path = fake_bin / name
            path.write_text(f"#!{sys.executable}\n" + FAKE_TOOL)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(fake_bin),
                                FAKE_ROOT=str(self.root), GITHUB_OUTPUT=str(self.github_output),
                                PYTHONDONTWRITEBYTECODE="1")

    def tearDown(self):
        # A broken helper must not leave this test's TERM-ignoring fake child.
        pid_file = self.root / "download-child.pid"
        if pid_file.exists():
            try:
                os.kill(int(pid_file.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.temporary.cleanup()

    def invoke(self, config=None, timeout=5):
        for path in (self.output, self.download):
            if path.exists():
                shutil.rmtree(path)
        for name in ("imported", "calls.jsonl", "created-name"):
            (self.root / name).unlink(missing_ok=True)
        self.github_output.write_text("")
        (self.root / "config.json").write_text(json.dumps(config or {}))
        started = time.monotonic()
        result = subprocess.run([sys.executable, str(SCRIPT), "--output", str(self.output),
                                 "--download-dir", str(self.download), "--timeout-seconds", str(timeout)],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        status = json.loads((self.output / "provision.json").read_text())
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertTrue(list(self.output.glob("command*-*.log")))
        return result, status, calls, time.monotonic() - started

    def assert_failed(self, config, timeout=5):
        result, status, calls, elapsed = self.invoke(config, timeout)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(status["outcome"], ("failure", "error"))
        self.assertEqual(self.github_output.read_text(), "")
        return status, calls, elapsed

    def assert_success(self, config=None):
        result, status, calls, _ = self.invoke(config)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(status["outcome"], "success")
        self.assertEqual(status["createdSimulatorID"], UDID)
        self.assertEqual(self.github_output.read_text().strip(), f"id={UDID}")
        create = next(call for call in calls if call[:3] == ["xcrun", "simctl", "create"])
        self.assertEqual(create[-2:], [DEVICE_TYPE, RUNTIME])
        return calls

    def test_installed_exact_runtime_does_not_download_or_import(self):
        calls = self.assert_success()
        self.assertEqual(calls[0], ["xcodebuild", "-version"])
        self.assertFalse(any(call[0] == "xcodebuild" and call[1] != "-version" for call in calls))

    def test_missing_runtime_imports_dmg_with_exact_download_pin(self):
        calls = self.assert_success({"runtime": "missing"})
        download = next(call for call in calls if "-downloadPlatform" in call)
        self.assertEqual(download, ["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", "22G86",
                                    "-architectureVariant", "arm64", "-exportPath", str(self.download)])
        self.assertIn(["xcodebuild", "-runFirstLaunch"], calls)
        imported = next(call for call in calls if "-importPlatform" in call)
        self.assertEqual(Path(imported[-1]).suffix, ".dmg")

    def test_missing_runtime_imports_complete_modern_bundles(self):
        for extension in (".exportedBundle", ".exportBundle"):
            with self.subTest(extension=extension):
                with tempfile.TemporaryDirectory() as directory:
                    # The nested payload proves discovery imports the whole bundle.
                    self.download = Path(directory) / "downloads"
                    calls = self.assert_success({"runtime": "missing", "package": extension})
                    imported = next(call for call in calls if "-importPlatform" in call)
                    self.assertEqual(Path(imported[-1]).suffix, extension)
                    self.assertTrue(Path(imported[-1]).is_dir())

    def test_wrong_existing_runtime_identity_or_availability_fails_without_download(self):
        for mode in ("wrongBuild", "wrongVersion", "unavailable", "availabilityNumber",
                     "missingFields", "duplicate", "malformed"):
            with self.subTest(mode=mode):
                status, calls, _ = self.assert_failed({"runtime": mode})
                self.assertFalse(any("-downloadPlatform" in call for call in calls))
                self.assertNotIn("createdSimulatorID", status)

    def test_wrong_xcode_version_or_build_fails_before_simulator_commands(self):
        for toolchain in ("Xcode 27.0\nBuild version 27A9269", "Xcode 27.1\nBuild version wrong"):
            with self.subTest(toolchain=toolchain):
                _, calls, _ = self.assert_failed({"toolchain": toolchain})
                self.assertFalse(any(call[0] == "xcrun" for call in calls))

    def test_missing_or_ambiguous_export_fails_before_import(self):
        for package in ("none", "multiple"):
            with self.subTest(package=package):
                _, calls, _ = self.assert_failed({"runtime": "missing", "package": package})
                self.assertFalse(any("-importPlatform" in call for call in calls))

    def test_post_import_identity_must_match_before_device_creation(self):
        for mode in ("wrongBuild", "missing", "unavailable"):
            with self.subTest(mode=mode):
                _, calls, _ = self.assert_failed({"runtime": "missing", "postRuntime": mode})
                self.assertFalse(any(call[:3] == ["xcrun", "simctl", "create"] for call in calls))

    def test_exact_device_type_is_required(self):
        _, calls, _ = self.assert_failed({"missingType": True})
        self.assertFalse(any(call[:3] == ["xcrun", "simctl", "create"] for call in calls))

    def test_create_output_must_be_a_single_uuid(self):
        status, calls, _ = self.assert_failed({"createOutput": f"warning\n{UDID}"})
        self.assertNotIn("createdSimulatorID", status)
        self.assertFalse(any(call[-1:] == ["devices"] for call in calls))

    def assert_create_warning_retained(self, warning):
        logs = list(self.output.glob("command*-create-device.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn(warning, logs[0].read_text())
        stdout = logs[0].with_suffix(".stdout").read_text()
        self.assertEqual(stdout.strip(), UDID)
        self.assertNotIn(warning, stdout)

    def test_create_stderr_warning_preserves_uuid_and_success_outputs(self):
        warning = "synthetic simctl warning on stderr"
        self.assert_success({"createWarning": warning})
        self.assert_create_warning_retained(warning)

    def test_create_stderr_warning_preserves_owned_uuid_on_post_validation_failure(self):
        warning = "synthetic simctl warning on stderr"
        status, _, _ = self.assert_failed({"createWarning": warning, "device": "wrongType"})
        self.assertEqual(status["createdSimulatorID"], UDID)
        self.assert_create_warning_retained(warning)

    def test_created_device_identity_and_availability_are_revalidated(self):
        for mode in ("wrongRuntime", "wrongType", "unavailable", "missing", "duplicate"):
            with self.subTest(mode=mode):
                status, _, _ = self.assert_failed({"device": mode})
                self.assertEqual(status["createdSimulatorID"], UDID)

    def test_download_failure_does_not_import_or_create(self):
        _, calls, _ = self.assert_failed({"runtime": "missing", "downloadFailure": True})
        self.assertFalse(any("-importPlatform" in call or "create" in call for call in calls))

    def test_download_timeout_is_bounded_and_does_not_import(self):
        _, calls, elapsed = self.assert_failed({"runtime": "missing", "downloadHang": True}, timeout=1)
        self.assertLess(elapsed, 5)
        self.assertFalse(any("-importPlatform" in call for call in calls))

    def test_download_timeout_kills_term_ignoring_descendant_after_leader_exits(self):
        _, calls, elapsed = self.assert_failed({"runtime": "missing", "downloadChild": True}, timeout=1)
        self.assertLess(elapsed, 5)
        self.assertFalse(any("-importPlatform" in call for call in calls))
        self.assertTrue((self.root / "leader-term-exit").is_file())
        self.assertTrue((self.root / "child-term-seen").is_file())
        child_pid = int((self.root / "download-child.pid").read_text())
        # Probe only the fake PID recorded by this test, allowing launchd to reap it.
        reap_by = time.monotonic() + 1
        while time.monotonic() < reap_by:
            try:
                os.kill(child_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(.02)
        else:
            self.fail("Owned fake download descendant survived helper timeout cleanup")

    def test_timeout_is_one_shared_budget_across_commands(self):
        _, _, elapsed = self.assert_failed({"runtime": "missing", "commandDelay": .25}, timeout=1)
        self.assertLess(elapsed, 5)


if __name__ == "__main__":
    unittest.main()
