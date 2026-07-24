#!/usr/bin/env bash

set -euo pipefail

if (( $# > 2 )); then
  echo "Usage: $0 <iOS major version> [iPhone|iPad]" >&2
  exit 64
fi

ios_major_version="${1:-26}"
device_family="${2:-iPhone}"

if ! [[ "$ios_major_version" =~ ^[0-9]+$ ]]; then
  echo "Expected an iOS major version, received: $ios_major_version" >&2
  exit 64
fi

if [[ "$device_family" != "iPhone" && "$device_family" != "iPad" ]]; then
  echo "Expected a device family of iPhone or iPad, received: $device_family" >&2
  exit 64
fi

runtime_prefix="com.apple.CoreSimulator.SimRuntime.iOS-${ios_major_version}-"

simulator_id="$(
  xcrun simctl list --json devices available \
    | jq -r \
      --arg runtime_prefix "$runtime_prefix" \
      --arg device_family "$device_family" '
        [
          .devices
          | to_entries
          | map(select(.key | startswith($runtime_prefix)))
          | sort_by(.key)
          | reverse
          | .[].value[]
          | select(.isAvailable == true)
          | select(.name | startswith($device_family))
          | .udid
        ]
        | first // empty
      '
)"

if [[ -z "$simulator_id" ]]; then
  echo "No available ${device_family} simulator with iOS ${ios_major_version}.x was found." >&2
  echo "Installed simulator runtimes:" >&2
  xcrun simctl list runtimes >&2
  exit 1
fi

echo "$simulator_id"
