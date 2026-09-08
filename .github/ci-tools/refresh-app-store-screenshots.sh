#!/usr/bin/env bash
set -euo pipefail

# This deliberately supports one reviewed scene replacement, not arbitrary
# screenshot splicing. The Python helper owns capture and offline provenance.
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "${script_directory}/app-store-screenshot-provenance.py" capture "$@"
