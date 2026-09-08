#!/usr/bin/env python3
"""Synthetic byte fixtures test provenance only; these are never release images."""

import copy
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("provenance", Path(__file__).resolve().parents[1] / "app-store-screenshot-provenance.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def create_fixture(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=True)
    old_context = root / "base-input-context.json"
    p.write(old_context, {"publicHead": "base-commit", "files": {"Surround/Localizable.xcstrings": "product-catalog", "SurroundUITests/AppStoreScreenshotTests.swift": "old-test"}})
    verification = root / "base-input-verification.json"
    p.write(verification, {"allRecordedInputsMatch": True, "captureContextSHA256": p.digest(old_context)})
    for kind in ("base", "refresh"):
        origin = root / kind
        origin.mkdir()
        scenes = {"iphone-6.9": p.PHONE, "ipad-13": p.PAD} if kind == "base" else {"iphone-6.9": ["04-quick-match"]}
        devices = {family: {"id": kind + "-" + family, "name": kind + " " + family} for family in scenes}
        metadata = {"locales": p.LOCALES, "scenes": scenes, "devices": devices,
                    "expectedScreenshotCount": 260 if kind == "base" else 13,
                    "runtime": {"name": "iOS fixture", "version": "1", "identifier": "fixture"},
                    "xcodeVersion": "fixture"}
        p.write(origin / "run-metadata.json", metadata)
        (origin / "AppStoreScreenshots.xcresult").mkdir()
        (origin / "AppStoreScreenshots.xcresult/data").write_bytes(b"synthetic result evidence")
        (origin / "xcodebuild.log").write_text("synthetic test passed\n")
        (origin / "attachments").mkdir()
        entries = []
        for index, path in enumerate(sorted(p.screenshot_paths(scenes))):
            _, locale, family, filename = path.split("/")
            target = origin / path
            target.parent.mkdir(parents=True, exist_ok=True)
            payload = (kind + path).encode()
            target.write_bytes(payload)
            raw_name = str(index) + ".png"
            (origin / "attachments" / raw_name).write_bytes(payload)
            entries.append({"configurationName": locale, "deviceId": devices[family]["id"],
                            "deviceName": devices[family]["name"], "exportedFileName": raw_name,
                            "suggestedHumanReadableName": filename, "isAssociatedWithFailure": False})
        p.write(origin / "attachments/manifest.json", [{"testIdentifier": (p.BASE_TEST if kind == "base" else p.REFRESH_TEST) + "()", "attachments": entries}])
        if kind == "refresh":
            p.write(origin / "input-context.json", {"schemaVersion": 1, "basePublicHead": "base-commit",
                    "baseInputContextSHA256": p.digest(old_context), "shippingTreeUnchanged": True,
                    "changedTrackedPaths": ["SurroundUITests/AppStoreScreenshotTests.swift"],
                    "files": {"Surround/Localizable.xcstrings": "product-catalog", "SurroundUITests/AppStoreScreenshotTests.swift": "new-test"}})
    output = root / "capture"
    p.assemble(root / "base", root / "refresh", old_context, verification, output)
    return output


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.capture = create_fixture(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def rewrite_ledger(self, ledger):
        p.write(self.capture / "screenshot-provenance.json", ledger)
        metadata = p.read(self.capture / "run-metadata.json")
        metadata["provenanceSHA256"] = p.digest(self.capture / "screenshot-provenance.json")
        p.write(self.capture / "run-metadata.json", metadata)

    def test_exact_complete_matrix_retains_247_sources(self):
        self.assertEqual(p.verify(self.capture), {"status": "pass", "mode": "scene-refresh", "screenshotCount": 260, "retainedCount": 247, "refreshedCount": 13})

    def test_retained_image_change_rejected(self):
        (self.capture / "screenshots/en-US/ipad-13/01-game-board.png").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            p.verify(self.capture)

    def test_refreshed_image_change_rejected(self):
        (self.capture / "screenshots/en-US/iphone-6.9/04-quick-match.png").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            p.verify(self.capture)

    def test_ledger_hash_change_rejected(self):
        ledger = p.read(self.capture / "screenshot-provenance.json")
        ledger["replacement"]["addedScene"] = "04-open-challenges"
        p.write(self.capture / "screenshot-provenance.json", ledger)
        with self.assertRaisesRegex(ValueError, "ledger hash"):
            p.verify(self.capture)

    def test_raw_attachment_or_result_change_rejected(self):
        for relative in ("origins/refresh/attachments/0.png", "origins/base/AppStoreScreenshots.xcresult/data"):
            target = self.capture / relative
            original = target.read_bytes()
            target.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "evidence hash"):
                p.verify(self.capture)
            target.write_bytes(original)

    def test_origin_mapping_cannot_relabel_old_scene(self):
        ledger = p.read(self.capture / "screenshot-provenance.json")
        row = next(row for row in ledger["images"] if row["origin"] == "refresh")
        row["origin"] = "base"
        self.rewrite_ledger(ledger)
        with self.assertRaisesRegex(ValueError, "Wrong origin"):
            p.verify(self.capture)

    def test_missing_duplicate_or_extra_output_rejected(self):
        ledger = p.read(self.capture / "screenshot-provenance.json")
        ledger["images"][0] = copy.deepcopy(ledger["images"][1])
        self.rewrite_ledger(ledger)
        with self.assertRaisesRegex(ValueError, "output matrix"):
            p.verify(self.capture)

    def test_source_context_cannot_allow_product_change(self):
        origin = self.capture / "origins/refresh"
        context = p.read(origin / "input-context.json")
        context["changedTrackedPaths"] += ["Surround/Views/MainView.swift"]
        p.write(origin / "input-context.json", context)
        ledger = p.read(self.capture / "screenshot-provenance.json")
        ledger["origins"]["refresh"]["files"] = p.inventory(origin)
        self.rewrite_ledger(ledger)
        with self.assertRaisesRegex(ValueError, "Shipping source changed"):
            p.verify(self.capture)

    def test_wrong_test_attachment_rejected_even_with_rehashed_inventory(self):
        origin = self.capture / "origins/refresh"
        manifest = p.read(origin / "attachments/manifest.json")
        manifest[0]["testIdentifier"] = p.BASE_TEST
        p.write(origin / "attachments/manifest.json", manifest)
        ledger = p.read(self.capture / "screenshot-provenance.json")
        ledger["origins"]["refresh"]["files"] = p.inventory(origin)
        self.rewrite_ledger(ledger)
        with self.assertRaisesRegex(ValueError, "Attachment evidence"):
            p.verify(self.capture)

    def test_symlink_output_rejected(self):
        target = self.capture / "screenshots/en-US/iphone-6.9/04-quick-match.png"
        target.unlink()
        target.symlink_to(self.capture / "origins/refresh/screenshots/en-US/iphone-6.9/04-quick-match.png")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            p.verify(self.capture)

    def test_single_result_bundle_claim_rejected(self):
        metadata = p.read(self.capture / "run-metadata.json")
        metadata["resultBundle"] = "origins/refresh/AppStoreScreenshots.xcresult"
        p.write(self.capture / "run-metadata.json", metadata)
        with self.assertRaisesRegex(ValueError, "both original result"):
            p.verify(self.capture)

    def test_plan_copy_selects_only_guarded_pilot_without_changing_source(self):
        source = self.root / "Original.xctestrun"
        destination = self.root / "Copied.xctestrun"
        data = {"TestConfigurations": [{"Name": locale, "TestTargets": [{"TestBundlePath": "__TESTROOT__/Tests.xctest", "OnlyTestIdentifiers": [p.BASE_TEST], "SkipTestIdentifiers": [p.REFRESH_TEST]}]} for locale in p.LOCALES]}
        source.write_bytes(plistlib.dumps(data))
        original = source.read_bytes()
        p.prepare_plan(source, destination)
        self.assertEqual(source.read_bytes(), original)
        for configuration in plistlib.loads(destination.read_bytes())["TestConfigurations"]:
            target = configuration["TestTargets"][0]
            self.assertEqual(target["OnlyTestIdentifiers"], [p.REFRESH_TEST + "()"])
            self.assertEqual(target["EnvironmentVariables"]["SURROUND_QUICK_MATCH_MARKETING_PILOT"], "1")
            self.assertNotIn("SkipTestIdentifiers", target)
            self.assertNotIn("__TESTROOT__", target["TestBundlePath"])

    def test_output_cannot_enter_origin_through_symlink_parent(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root / "base", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "within an origin"):
            p.new_output_path(alias / "new-output", self.root / "base")
        self.assertFalse((self.root / "base/new-output").exists())

    def test_output_cannot_enter_origin_through_parent_traversal(self):
        (self.root / "outside").mkdir()
        with self.assertRaisesRegex(ValueError, "within an origin"):
            p.new_output_path(self.root / "outside/../base/new-output", self.root / "base")
        self.assertFalse((self.root / "base/new-output").exists())

    def test_assemble_rejects_nested_destination_before_writing(self):
        with self.assertRaisesRegex(ValueError, "within an origin"):
            p.assemble(self.root / "base", self.root / "refresh", self.root / "base-input-context.json", self.root / "base-input-verification.json", self.root / "base/should-not-exist")
        self.assertFalse((self.root / "base/should-not-exist").exists())

    def test_empty_extra_family_directory_rejected(self):
        (self.capture / "screenshots/en-US/extra-family").mkdir()
        with self.assertRaisesRegex(ValueError, "family directory"):
            p.verify(self.capture)

    def test_capture_rejects_derived_ancestor_or_child_before_writing(self):
        output = self.root / "new-capture"
        work = self.root / "new-capture.refresh-work"
        for derived in (self.root, self.root / "base/Build", output / "Build", work / "Build"):
            with self.subTest(derived=derived):
                args = argparse.Namespace(base_capture=str(self.root / "base"),
                    base_input_context=str(self.root / "base-input-context.json"),
                    base_input_verification=str(self.root / "base-input-verification.json"),
                    output=str(output), derived_data=str(derived), device_name=None)
                with self.assertRaisesRegex(ValueError, "must be disjoint"):
                    p.capture(args)
                self.assertFalse(output.exists())
                self.assertFalse(work.exists())

    def test_disjoint_sibling_cache_and_capture_paths_allowed(self):
        p.require_disjoint_paths(self.root / "cache", self.root / "base",
                                 self.root / "new-capture", self.root / "new-capture.refresh-work")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--create-fixture":
        print(create_fixture(Path(sys.argv[2])))
    else:
        unittest.main()
