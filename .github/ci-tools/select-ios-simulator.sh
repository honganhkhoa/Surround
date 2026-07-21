#!/usr/bin/env bash

set -euo pipefail

ios_major_version="${1:-26}"

if ! [[ "$ios_major_version" =~ ^[0-9]+$ ]]; then
  echo "Expected an iOS major version, received: $ios_major_version" >&2
  exit 64
fi

runtime_prefix="com.apple.CoreSimulator.SimRuntime.iOS-${ios_major_version}-"

simulator_id="$(
  xcrun simctl list --json devices available \
    | jq -r --arg runtime_prefix "$runtime_prefix" '
        [
          .devices
          | to_entries
          | map(select(.key | startswith($runtime_prefix)))
          | sort_by(.key)
          | reverse
          | .[].value[]
          | select(.isAvailable == true)
          | select(.name | startswith("iPhone"))
          | .udid
        ]
        | first // empty
      '
)"

if [[ -z "$simulator_id" ]]; then
  echo "No available iPhone simulator with iOS ${ios_major_version}.x was found." >&2
  echo "Installed simulator runtimes:" >&2
  xcrun simctl list runtimes >&2
  exit 1
fi

echo "$simulator_id"
