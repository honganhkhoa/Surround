#!/usr/bin/env python3
"""Install the comparison apps without touching the real Surround app."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Paired device name or UDID')
args = parser.parse_args()
base = Path(__file__).resolve().parent
variants = json.loads((base / 'variants.json').read_text())
products = base / '.build/DerivedData/Build/Products/Debug-iphoneos'
records = base / '.build/Deployment'
records.mkdir(parents=True, exist_ok=True)
apps = []
for variant in variants:
    app = products / (variant['target'] + '.app')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    expected = 'com.honganhkhoa.Surround.IconStudy.' + variant['id']
    if info['CFBundleIdentifier'] != expected:
        raise SystemExit(f'Refusing unexpected app identifier: {info["CFBundleIdentifier"]}')
    if not (app / 'Assets.car').is_file():
        raise SystemExit(f'Missing compiled icon assets: {app}')
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    apps.append((variant, app))

for variant, app in apps:
    print('Installing ' + variant['label'] + '…', flush=True)
    subprocess.run([
        'xcrun', 'devicectl', 'device', 'install', 'app',
        '--device', args.device, str(app),
        '--json-output', str(records / (variant['id'] + '.json')),
        '--timeout', '60'
    ], check=True)
print(f'All {len(apps)} comparison apps installed.', flush=True)
