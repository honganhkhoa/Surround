#!/usr/bin/env python3
"""Offline, fail-closed provenance for the bounded iPhone Quick Match refresh.

This records reuse; it never claims the assembled matrix came from one test run.
PNG decoding remains the responsibility of the normalizer and release image gates.
"""

import argparse
import copy
import hashlib
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone

LOCALES = ["en-US", "fr-FR", "de-DE", "ja-JP", "vi-VN", "th-TH", "zh-Hans-CN",
           "zh-Hant-TW", "ko-KR", "es-ES", "es-MX", "pt-BR", "pt-PT"]
PHONE = ["01-game-board", "02-active-games", "03-game-chat", "04-open-challenges",
         "05-game-analysis", "06-zen-mode", "07-preferred-settings", "08-public-games",
         "09-conditional-moves", "10-home-screen-widget"]
PAD = ["01-game-board", "02-active-games", "03-game-analysis", "04-zen-mode",
       "05-conditional-moves", "06-public-games", "07-quick-match", "08-open-challenges",
       "09-preferred-settings", "10-home-screen-widget"]
REPLACEMENT = {"family": "iphone-6.9", "removedScene": "04-open-challenges",
               "addedScene": "04-quick-match"}
NEW_PHONE = [REPLACEMENT["addedScene"] if s == REPLACEMENT["removedScene"] else s for s in PHONE]
BASE_TEST = "AppStoreScreenshotTests/testAppStoreScreenshots"
REFRESH_TEST = "AppStoreScreenshotTests/testQuickMatchMarketingPilot"
ALLOWED_CHANGES = {"SurroundUITests/AppStoreScreenshotTests.swift", "TESTING.md",
                   ".github/ci-tools/capture-app-store-screenshots.sh",
                   ".github/ci-tools/refresh-app-store-screenshots.sh",
                   ".github/ci-tools/app-store-screenshot-provenance.py",
                   ".github/ci-tools/tests/test_app_store_screenshot_provenance.py"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def relative_file(root, relative):
    require(isinstance(relative, str) and relative and not relative.startswith("/"), "Expected relative evidence path")
    parts = Path(relative).parts
    require(all(p not in (".", "..") for p in parts), "Unsafe evidence path")
    path = root
    for part in parts:
        path = path / part
        require(not path.is_symlink(), "Symlink evidence is not permitted: " + relative)
    require(path.is_file() and path.resolve().is_relative_to(root.resolve()), "Missing evidence file: " + relative)
    return path


def inventory(root):
    result = {}
    for path in sorted(root.rglob("*")):
        require(not path.is_symlink(), "Symlink in evidence: " + str(path))
        if path.is_file():
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def screenshot_paths(scenes):
    return {f"screenshots/{locale}/{family}/{scene}.png"
            for locale in LOCALES for family, names in scenes.items() for scene in names}


def actual_screenshots(root):
    directory = root / "screenshots"
    require(directory.is_dir() and not directory.is_symlink(), "Missing screenshot root")
    paths = set()
    for p in directory.rglob("*"):
        require(not p.is_symlink(), "Symlink screenshot")
        if p.is_file():
            require(p.suffix == ".png", "Unexpected screenshot entry")
            paths.add(p.relative_to(root).as_posix())
    require({p.name for p in directory.iterdir()} == set(LOCALES), "Wrong screenshot locale directories")
    for locale in LOCALES:
        families = {path.split("/")[2] for path in paths if path.split("/")[1] == locale}
        require({p.name for p in (directory / locale).iterdir()} == families, "Unexpected screenshot family directory")
    return paths


def new_output_path(value, *protected_roots):
    # Resolve existing symlink ancestors and '..' before checking containment;
    # otherwise copying an origin into itself can recurse and mutate evidence.
    destination = Path(value).expanduser().resolve(strict=False)
    require(not destination.exists(), "Output already exists")
    for protected in protected_roots:
        protected = Path(protected).resolve(strict=True)
        require(not destination.is_relative_to(protected), "Output must not be within an origin")
    return destination


def require_disjoint_paths(first, *others):
    first = Path(first).resolve(strict=False)
    for other in others:
        other = Path(other).resolve(strict=False)
        require(not first.is_relative_to(other) and not other.is_relative_to(first),
                "DerivedData and capture evidence paths must be disjoint")


def attachments(root, metadata, scenes, test_name):
    manifest = read(root / "attachments/manifest.json")
    require(isinstance(manifest, list), "Invalid attachment manifest")
    found = {}
    ids = {v["id"]: family for family, v in metadata["devices"].items()}
    for test in manifest:
        identifier = test.get("testIdentifier", "")
        if identifier.rstrip("()") != test_name:
            continue
        for entry in test.get("attachments", []):
            family = ids.get(entry.get("deviceId"))
            require(family is not None, "Unexpected attachment device")
            name = entry.get("suggestedHumanReadableName", "")
            matches = [s for s in scenes[family] if name == s + ".png" or name.startswith(s + "_")]
            if not matches:
                continue
            require(len(matches) == 1 and not entry.get("isAssociatedWithFailure", False), "Invalid screenshot attachment")
            locale = entry.get("configurationName")
            require(locale in LOCALES, "Unexpected attachment locale")
            key = f"screenshots/{locale}/{family}/{matches[0]}.png"
            require(key not in found, "Duplicate screenshot attachment: " + key)
            exported = entry.get("exportedFileName", "")
            require(Path(exported).name == exported, "Unsafe exported attachment filename")
            raw = relative_file(root, "attachments/" + exported)
            found[key] = {"path": "attachments/" + exported, "sha256": digest(raw),
                          "testIdentifier": identifier, "deviceId": entry["deviceId"],
                          "deviceName": entry["deviceName"], "configurationName": locale,
                          "suggestedHumanReadableName": name}
    require(set(found) == screenshot_paths(scenes), "Attachment evidence does not cover the exact scene matrix")
    return found


def validate_origin(root, kind):
    metadata = read(root / "run-metadata.json")
    scenes = {"iphone-6.9": PHONE, "ipad-13": PAD} if kind == "base" else {"iphone-6.9": ["04-quick-match"]}
    require(metadata.get("locales") == LOCALES, "Origin locales do not match")
    require(metadata.get("scenes") == scenes, "Origin scene contract does not match")
    require(metadata.get("expectedScreenshotCount") == (260 if kind == "base" else 13), "Origin screenshot count does not match")
    require(set(metadata.get("devices", {})) == set(scenes), "Origin device families do not match")
    require(actual_screenshots(root) == screenshot_paths(scenes), "Origin screenshots do not match the exact matrix")
    require((root / "AppStoreScreenshots.xcresult").is_dir(), "Original result bundle missing")
    require(any((root / "AppStoreScreenshots.xcresult").rglob("*")), "Original result bundle empty")
    return metadata, attachments(root, metadata, scenes, BASE_TEST if kind == "base" else REFRESH_TEST)


def validate_contexts(base, refresh):
    old = read(base / "input-context.json")
    committed = read(base / "input-verification.json")
    current = read(refresh / "input-context.json")
    require(committed.get("allRecordedInputsMatch") is True, "Base input verification did not pass")
    require(committed.get("captureContextSHA256") == digest(base / "input-context.json"), "Base context hash mismatch")
    require(current.get("schemaVersion") == 1, "Current input context schema mismatch")
    require(current.get("basePublicHead") == old.get("publicHead"), "Source revision mismatch")
    require(current.get("baseInputContextSHA256") == digest(base / "input-context.json"), "Current context does not bind original input context")
    changed = current.get("changedTrackedPaths")
    require(isinstance(changed, list) and set(changed) <= ALLOWED_CHANGES, "Shipping source changed since original capture")
    require(current.get("shippingTreeUnchanged") is True, "Shipping source comparison did not pass")
    for path, original_hash in old.get("files", {}).items():
        if path.startswith(("AppStoreReleases/", "AppStoreScreenshotTools/")) or path in ALLOWED_CHANGES:
            continue
        require(current.get("files", {}).get(path) == original_hash, "Recorded product input changed: " + path)
    require(current.get("files", {}).get("SurroundUITests/AppStoreScreenshotTests.swift"), "Current screenshot test hash missing")
    return current


def verify(capture_root):
    root = Path(capture_root).resolve(strict=True)
    metadata = read(root / "run-metadata.json")
    require(metadata.get("mode") == "scene-refresh", "Expected scene-refresh mode")
    require(metadata.get("provenanceFile") == "screenshot-provenance.json", "Unexpected provenance file")
    ledger_path = relative_file(root, "screenshot-provenance.json")
    require(digest(ledger_path) == metadata.get("provenanceSHA256"), "Provenance ledger hash mismatch")
    ledger = read(ledger_path)
    require(ledger.get("schemaVersion") == 1 and ledger.get("mode") == "scene-refresh", "Unknown provenance schema")
    require(ledger.get("replacement") == REPLACEMENT and ledger.get("locales") == LOCALES, "Unexpected replacement contract")
    origins = {}
    for kind in ("base", "refresh"):
        record = ledger["origins"][kind]
        prefix = "origins/" + kind
        require(record.get("path") == prefix, "Unexpected origin root")
        origin = root / prefix
        require(origin.is_dir() and not origin.is_symlink(), "Origin directory missing")
        require(inventory(origin) == record.get("files"), "Origin evidence hash mismatch: " + kind)
        require(record.get("metadataSHA256") == digest(origin / "run-metadata.json"), "Origin metadata hash mismatch")
        origins[kind] = validate_origin(origin, kind)
    require(set(ledger["origins"]) == {"base", "refresh"}, "Unexpected origin")
    base_meta, base_attachments = origins["base"]
    refresh_meta, refresh_attachments = origins["refresh"]
    require(base_meta["runtime"] == refresh_meta["runtime"] and base_meta["xcodeVersion"] == refresh_meta["xcodeVersion"], "Capture runtime or Xcode differs")
    validate_contexts(root / "origins/base", root / "origins/refresh")
    expected = screenshot_paths({"iphone-6.9": NEW_PHONE, "ipad-13": PAD})
    require(actual_screenshots(root) == expected, "Assembled screenshots do not match the exact matrix")
    require(metadata.get("locales") == LOCALES and metadata.get("scenes") == {"iphone-6.9": NEW_PHONE, "ipad-13": PAD}, "Aggregate scene or locale metadata mismatch")
    require(metadata.get("expectedScreenshotCount") == 260, "Aggregate screenshot count mismatch")
    require(metadata.get("runtime") == base_meta["runtime"] and metadata.get("xcodeVersion") == base_meta["xcodeVersion"], "Aggregate environment mismatch")
    require(metadata.get("devices") == {"iphone-6.9": {"origins": [base_meta["devices"]["iphone-6.9"], refresh_meta["devices"]["iphone-6.9"]]}, "ipad-13": base_meta["devices"]["ipad-13"]}, "Aggregate device provenance mismatch")
    require("resultBundle" not in metadata and metadata.get("resultBundles") == ["origins/base/AppStoreScreenshots.xcresult", "origins/refresh/AppStoreScreenshots.xcresult"], "Aggregate must identify both original result bundles")
    images = ledger.get("images", [])
    require(len(images) == 260 and {row["path"] for row in images} == expected, "Provenance output matrix mismatch")
    counts = {"base": 0, "refresh": 0}
    for row in images:
        path = row["path"]
        kind = "refresh" if path.endswith("/iphone-6.9/04-quick-match.png") else "base"
        require(row.get("origin") == kind, "Wrong origin for output: " + path)
        expected_origin_path = f"origins/{kind}/{path}"
        require(row.get("originPath") == expected_origin_path, "Origin image mapping mismatch")
        origin_path = relative_file(root, expected_origin_path)
        source_hash = digest(origin_path)
        require(row.get("sha256") == row.get("sourceSHA256") == source_hash == digest(relative_file(root, path)), "Retained or refreshed screenshot bytes changed: " + path)
        expected_attachment = copy.deepcopy((base_attachments if kind == "base" else refresh_attachments)[path])
        expected_attachment["path"] = f"origins/{kind}/" + expected_attachment["path"]
        require(row.get("attachment") == expected_attachment, "Attachment provenance mismatch: " + path)
        counts[kind] += 1
    require(counts == {"base": 247, "refresh": 13}, "Replacement counts mismatch")
    return {"status": "pass", "mode": "scene-refresh", "screenshotCount": 260, "retainedCount": 247, "refreshedCount": 13}


def input_context(repository, base_context, output):
    repo = Path(repository).resolve(strict=True)
    old_path = Path(base_context).resolve(strict=True)
    old = read(old_path)
    head = old["publicHead"]
    git = lambda *args: subprocess.check_output(["git", "-c", "core.fsmonitor=false", "-C", str(repo), *args], text=True).strip()
    changed = git("diff", "--name-only", head, "--").splitlines()
    require(set(changed) <= ALLOWED_CHANGES, "Shipping source differs from original capture: " + ", ".join(sorted(set(changed) - ALLOWED_CHANGES)))
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    require(set(untracked) <= ALLOWED_CHANGES, "Unreviewed untracked inputs exist: " + ", ".join(sorted(set(untracked) - ALLOWED_CHANGES)))
    files = {p: digest(repo / p) for p in set(old["files"]) | ALLOWED_CHANGES if (repo / p).is_file()}
    value = {"schemaVersion": 1, "recordedAt": datetime.now(timezone.utc).isoformat(), "basePublicHead": head,
             "publicHead": git("rev-parse", "HEAD"), "baseInputContextSHA256": digest(old_path),
             "changedTrackedPaths": changed, "untrackedPaths": untracked, "shippingTreeUnchanged": True, "files": files}
    write(output, value)


def assemble(base_capture, refresh_capture, base_context, base_verification, output):
    base = Path(base_capture).resolve(strict=True)
    fresh = Path(refresh_capture).resolve(strict=True)
    destination = new_output_path(output, base, fresh)
    base_meta, base_evidence = validate_origin(base, "base")
    fresh_meta, fresh_evidence = validate_origin(fresh, "refresh")
    destination.mkdir(parents=True)
    records = {}
    for kind, source in (("base", base), ("refresh", fresh)):
        target = destination / "origins" / kind
        target.mkdir(parents=True)
        # Preserve one actual aggregate bundle, not the duplicated intermediate bundles.
        for name in ("run-metadata.json", "screenshots", "attachments", "AppStoreScreenshots.xcresult", "xcodebuild.log"):
            item = source / name
            require(item.exists() and not item.is_symlink(), "Origin evidence missing: " + str(item))
            if item.is_dir():
                shutil.copytree(item, target / name, symlinks=True)
            else:
                shutil.copy2(item, target / name)
        if kind == "base":
            shutil.copy2(base_context, target / "input-context.json")
            shutil.copy2(base_verification, target / "input-verification.json")
        else:
            shutil.copy2(source / "input-context.json", target / "input-context.json")
        records[kind] = {"path": "origins/" + kind, "originalPath": str(source),
                         "metadataSHA256": digest(target / "run-metadata.json"), "files": inventory(target)}
    images = []
    for path in sorted(screenshot_paths({"iphone-6.9": NEW_PHONE, "ipad-13": PAD})):
        kind = "refresh" if path.endswith("/iphone-6.9/04-quick-match.png") else "base"
        source = destination / "origins" / kind / path
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        attachment = copy.deepcopy((base_evidence if kind == "base" else fresh_evidence)[path])
        attachment["path"] = f"origins/{kind}/" + attachment["path"]
        images.append({"path": path, "sha256": digest(target), "sourceSHA256": digest(source),
                       "origin": kind, "originPath": f"origins/{kind}/{path}", "attachment": attachment})
    ledger = {"schemaVersion": 1, "mode": "scene-refresh", "replacement": REPLACEMENT,
              "locales": LOCALES, "origins": records, "images": images}
    write(destination / "screenshot-provenance.json", ledger)
    metadata = {"mode": "scene-refresh", "generatedAt": datetime.now(timezone.utc).isoformat(),
                "xcodeVersion": fresh_meta["xcodeVersion"], "runtime": fresh_meta["runtime"],
                "devices": {"iphone-6.9": {"origins": [base_meta["devices"]["iphone-6.9"], fresh_meta["devices"]["iphone-6.9"]]},
                            "ipad-13": base_meta["devices"]["ipad-13"]}, "locales": LOCALES,
                "scenes": {"iphone-6.9": NEW_PHONE, "ipad-13": PAD}, "expectedScreenshotCount": 260,
                "resultBundles": ["origins/base/AppStoreScreenshots.xcresult", "origins/refresh/AppStoreScreenshots.xcresult"],
                "provenanceFile": "screenshot-provenance.json", "provenanceSHA256": digest(destination / "screenshot-provenance.json")}
    write(destination / "run-metadata.json", metadata)
    return verify(destination)


def prepare_plan(source, destination):
    source = Path(source)
    data = plistlib.loads(source.read_bytes())
    require([item["Name"] for item in data["TestConfigurations"]] == LOCALES, "Generated test configurations differ from the locale contract")

    def transform(value):
        if isinstance(value, str):
            return value.replace("__TESTROOT__", str(source.parent.resolve()))
        if isinstance(value, list):
            return [transform(item) for item in value]
        if isinstance(value, dict):
            result = {key: transform(item) for key, item in value.items() if key != "SkipTestIdentifiers"}
            if "TestBundlePath" in result:
                result["OnlyTestIdentifiers"] = [REFRESH_TEST + "()"]
                result.setdefault("EnvironmentVariables", {})["SURROUND_QUICK_MATCH_MARKETING_PILOT"] = "1"
            return result
        return value

    Path(destination).write_bytes(plistlib.dumps(transform(data)))


def capture(args):
    """Capture only the 13 changed scenes, then assemble and verify a new matrix."""
    repository = Path(__file__).resolve().parents[2]
    base = Path(args.base_capture).resolve(strict=True)
    base_context = Path(args.base_input_context).resolve(strict=True)
    base_verification = Path(args.base_input_verification).resolve(strict=True)
    output = new_output_path(args.output, base)
    work = output.with_name(output.name + ".refresh-work")
    work = new_output_path(work, base)
    base_meta, _ = validate_origin(base, "base")
    configuration = read(repository / ".github/ci-tools/app-store-release-locales.json")
    require([item["screenshotConfiguration"] for item in configuration["localizations"]] == LOCALES, "Public locale contract changed")
    derived = Path(args.derived_data or repository / ".build/AppStoreScreenshotDerivedData").resolve()
    require_disjoint_paths(derived, base, work, output)
    work.mkdir(parents=True)
    input_context(repository, base_context, work / "input-context.json")
    initial_context = read(work / "input-context.json")
    derived.mkdir(parents=True, exist_ok=True)
    # Credentials never reach build, Simulator, export or assembly subprocesses.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("ASC_")}
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    log_path = work / "xcodebuild.log"

    def run(command, output_text=False):
        if output_text:
            return subprocess.check_output(command, cwd=repository, env=environment, text=True).strip()
        print("Running: " + " ".join(map(str, command)), flush=True)
        with log_path.open("a") as log:
            process = subprocess.Popen(command, cwd=repository, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                log.write(line)
                print(line, end="", flush=True)
            code = process.wait()
        require(code == 0, "Capture command failed; original evidence is preserved in " + str(work))

    xcode_version = run(["xcodebuild", "-version"], True).splitlines()[0].split()[-1]
    require(xcode_version == base_meta["xcodeVersion"], "Reuse requires the original Xcode version")
    runtime_id = base_meta["runtime"]["identifier"]
    runtimes = json.loads(run(["xcrun", "simctl", "list", "--json", "runtimes"], True))["runtimes"]
    require(any(r["identifier"] == runtime_id and r.get("isAvailable") for r in runtimes), "Original Simulator runtime is unavailable")
    available = json.loads(run(["xcrun", "simctl", "list", "--json", "devices", "available"], True))["devices"].get(runtime_id, [])
    preferred = [args.device_name] if args.device_name else ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone Air", "iPhone 16 Plus", "iPhone 15 Pro Max", "iPhone 15 Plus", "iPhone 14 Pro Max"]
    template = next((d for name in preferred for d in available if d["name"] == name), None)
    require(template is not None, "No accepted iPhone template is available in the original runtime")
    device_name = "Surround Quick Match Refresh " + str(os.getpid())
    device_id = run(["xcrun", "simctl", "create", device_name, template["deviceTypeIdentifier"], runtime_id], True)
    require(len(device_id) == 36, "Disposable Simulator creation failed")
    try:
        run(["xcrun", "simctl", "boot", device_id])
        run(["xcrun", "simctl", "bootstatus", device_id, "-b"])
        run(["xcrun", "simctl", "status_bar", device_id, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4"])
        run(["xcodebuild", "build-for-testing", "-project", "Surround.xcodeproj", "-scheme", "AppStoreScreenshots", "-testPlan", "AppStoreScreenshots", "-configuration", "Debug", "-destination", "platform=iOS Simulator,id=" + device_id, "-derivedDataPath", str(derived), "-parallel-testing-enabled", "NO", "-only-testing:SurroundUITests/" + REFRESH_TEST])
        products = derived / "Build/Products"
        plans = list(products.glob("AppStoreScreenshots_AppStoreScreenshots_iphonesimulator" + base_meta["runtime"]["version"] + "-*.xctestrun"))
        require(len(plans) == 1, "Expected exactly one generated screenshot test plan for this runtime")
        copied_plan = work / "QuickMatchRefresh.xctestrun"
        prepare_plan(plans[0], copied_plan)
        bundles = []
        (work / "locale-results").mkdir()
        for locale in LOCALES:
            print("Capturing iPhone Quick Match: " + locale, flush=True)
            bundle = work / "locale-results" / (locale + ".xcresult")
            run(["xcodebuild", "test-without-building", "-xctestrun", str(copied_plan), "-destination", "platform=iOS Simulator,id=" + device_id, "-resultBundlePath", str(bundle), "-parallel-testing-enabled", "NO", "-only-test-configuration", locale])
            bundles.append(str(bundle))
        run(["xcrun", "xcresulttool", "merge", *bundles, "--output-path", str(work / "AppStoreScreenshots.xcresult")])
        run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(work / "AppStoreScreenshots.xcresult"), "--output-path", str(work / "attachments")])
        metadata = {"mode": "quick-match-refresh-origin", "generatedAt": datetime.now(timezone.utc).isoformat(),
                    "xcodeVersion": xcode_version, "runtime": base_meta["runtime"], "locales": LOCALES,
                    "devices": {"iphone-6.9": {"name": device_name, "id": device_id}},
                    "scenes": {"iphone-6.9": ["04-quick-match"]}, "expectedScreenshotCount": 13,
                    "resultBundle": str(work / "AppStoreScreenshots.xcresult")}
        write(work / "run-metadata.json", metadata)
        records = attachments(work, metadata, metadata["scenes"], REFRESH_TEST)
        normalizer = work / "normalize-app-store-screenshot"
        run(["xcrun", "swiftc", str(repository / ".github/ci-tools/normalize-app-store-screenshot.swift"), "-o", str(normalizer)])
        for path, entry in records.items():
            target = work / path
            target.parent.mkdir(parents=True, exist_ok=True)
            run([str(normalizer), str(work / entry["path"]), str(target)])
            run([str(normalizer), "--validate-neutral", str(target)])
        input_context(repository, base_context, work / "input-context-after.json")
        require(read(work / "input-context-after.json")["files"] == initial_context["files"], "Capture input files changed during the refresh")
        result = assemble(base, work, base_context, base_verification, output)
        print("Complete self-contained scene refresh: " + str(output), flush=True)
        return result
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device_id], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["xcrun", "simctl", "delete", device_id], env=environment, check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("verify")
    check.add_argument("--capture-root", required=True)
    context = commands.add_parser("input-context")
    context.add_argument("--repository", required=True)
    context.add_argument("--base-input-context", required=True)
    context.add_argument("--output", required=True)
    assembly = commands.add_parser("assemble")
    for flag in ("base-capture", "refresh-capture", "base-input-context", "base-input-verification", "output"):
        assembly.add_argument("--" + flag, required=True)
    capture_command = commands.add_parser("capture", help="Capture 13 Quick Match scenes and assemble a complete provenance-bound matrix")
    for flag in ("base-capture", "base-input-context", "base-input-verification", "output"):
        capture_command.add_argument("--" + flag, required=True)
    capture_command.add_argument("--derived-data")
    capture_command.add_argument("--device-name")
    args = parser.parse_args()
    try:
        if args.command == "verify":
            result = verify(args.capture_root)
        elif args.command == "input-context":
            input_context(args.repository, args.base_input_context, args.output)
            result = {"status": "pass", "inputContext": args.output}
        elif args.command == "capture":
            result = capture(args)
        else:
            result = assemble(args.base_capture, args.refresh_capture, args.base_input_context, args.base_input_verification, args.output)
        print(json.dumps(result))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
