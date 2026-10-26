#!/usr/bin/env python3
"""Theme preview import tests use temporary catalogs only, never the app's."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "update-theme-previews.py"


class UpdateThemePreviewsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.export = root / "ThemePreviews"
        self.catalog = root / "Assets.xcassets"
        self.debug_catalog = root / "DebugThemes.xcassets"
        self.export.mkdir()
        for name in ("standard-light", "standard-dark", "nebulaPearl-dark", "frostPine-light", "frostPine-dark"):
            (self.export / f"{name}.jpg").write_bytes(name.encode())
        (self.export / "themes.json").write_text(json.dumps({"debugOnly": ["frostPine", "feltMeadow"]}))
        (self.export / "done").write_text("done\n")
        # Stale thumbnails in both catalogs, as after a theme moves between them.
        for stale in (self.catalog / "ThemePreviews/ThemePreview-frostPine.imageset",
                      self.debug_catalog / "ThemePreviews/ThemePreview-standard.imageset"):
            stale.mkdir(parents=True)
            (stale / "Contents.json").write_text("{}")

    def tearDown(self):
        self.temporary.cleanup()

    def run_script(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.export),
                               "--catalog", str(self.catalog), "--debug-catalog", str(self.debug_catalog)],
                              capture_output=True, text=True)

    def imagesets(self, catalog):
        return sorted(path.name for path in (catalog / "ThemePreviews").glob("*.imageset"))

    def test_debug_only_thumbnails_join_the_debug_catalog(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.imagesets(self.catalog),
                         ["ThemePreview-nebulaPearl.imageset", "ThemePreview-standard.imageset"])
        self.assertEqual(self.imagesets(self.debug_catalog), ["ThemePreview-frostPine.imageset"])
        for catalog in (self.catalog, self.debug_catalog):
            self.assertEqual(json.loads((catalog / "ThemePreviews/Contents.json").read_text()),
                             {"info": {"author": "xcode", "version": 1}})
        frost = json.loads((self.debug_catalog / "ThemePreviews/ThemePreview-frostPine.imageset/Contents.json").read_text())
        self.assertEqual([image["filename"] for image in frost["images"]], ["frostPine.jpg", "frostPine-dark.jpg"])
        nebula = json.loads((self.catalog / "ThemePreviews/ThemePreview-nebulaPearl.imageset/Contents.json").read_text())
        self.assertEqual([image["filename"] for image in nebula["images"]], ["nebulaPearl.jpg"])

    def test_the_debug_catalog_defaults_to_the_catalogs_sibling(self):
        staging = Path(self.temporary.name) / "staging/Assets.xcassets"
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.export), "--catalog", str(staging)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.imagesets(staging.with_name("DebugThemes.xcassets")), ["ThemePreview-frostPine.imageset"])
        # The default catalogs' thumbnails are untouched.
        self.assertEqual(self.imagesets(self.debug_catalog), ["ThemePreview-standard.imageset"])

    def test_an_export_without_a_theme_list_changes_nothing(self):
        (self.export / "themes.json").unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("themes.json", result.stderr)
        self.assertEqual(self.imagesets(self.catalog), ["ThemePreview-frostPine.imageset"])
        self.assertEqual(self.imagesets(self.debug_catalog), ["ThemePreview-standard.imageset"])


if __name__ == "__main__":
    unittest.main()
