#!/usr/bin/env python3
"""Copies the app's exported theme previews into the asset catalog.

The theme pickers show these thumbnails instead of drawing every theme's
scene and board live. Export them from a Debug build on an iOS Simulator:

    xcrun simctl launch --terminate-running-process <udid> com.honganhkhoa.Surround \\
        --surround-ui-testing --surround-theme-preview-export

When `Documents/ThemePreviews/done` appears in the app's data container
(`xcrun simctl get_app_container <udid> com.honganhkhoa.Surround data`), run:

    .github/ci-tools/update-theme-previews.py <data container>/Documents/ThemePreviews

Each theme gets `ThemePreview-<theme>.imageset`: a light image with a dark
variant, or one image for an always-dark theme. The previous imagesets are
replaced. Standard library only.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[2] / "Surround/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}
DARK = [{"appearance": "luminosity", "value": "dark"}]


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, separators=(",", " : ")))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("export", type=Path, help="The app's Documents/ThemePreviews folder")
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    args = parser.parse_args()

    if not (args.export / "done").exists():
        sys.exit(f"{args.export} has no finished export (missing 'done').")
    themes = {}
    for image in sorted(args.export.glob("*.jpg")):
        theme, _, appearance = image.stem.rpartition("-")
        if appearance not in ("light", "dark") or not theme:
            sys.exit(f"Unexpected file name: {image.name}")
        themes.setdefault(theme, {})[appearance] = image
    if not themes:
        sys.exit(f"No previews in {args.export}.")

    folder = args.catalog / "ThemePreviews"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    write_json(folder / "Contents.json", {"info": INFO})
    for theme, images in themes.items():
        imageset = folder / f"ThemePreview-{theme}.imageset"
        imageset.mkdir()
        entries = []
        # An always-dark theme exports only its dark image, used everywhere.
        base = images.get("light") or images["dark"]
        shutil.copyfile(base, imageset / f"{theme}.jpg")
        entries.append({"filename": f"{theme}.jpg", "idiom": "universal"})
        if "light" in images and "dark" in images:
            shutil.copyfile(images["dark"], imageset / f"{theme}-dark.jpg")
            entries.append({"appearances": DARK, "filename": f"{theme}-dark.jpg", "idiom": "universal"})
        write_json(imageset / "Contents.json", {"images": entries, "info": INFO})
        print(f"{imageset.name}: {', '.join(sorted(images))}")


if __name__ == "__main__":
    main()
