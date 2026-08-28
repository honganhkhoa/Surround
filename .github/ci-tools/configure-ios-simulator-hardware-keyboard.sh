#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 <simulator UDID>" >&2
  exit 64
fi

simulator_id="$1"

if ! [[ "$simulator_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "Expected a simulator UDID, received: $simulator_id" >&2
  exit 64
fi

if ! xcrun simctl list --json devices available \
  | jq -e --arg simulator_id "$simulator_id" '
      any(
        .devices[][];
        .udid == $simulator_id and .isAvailable == true
      )
    ' >/dev/null; then
  echo "No available simulator has UDID $simulator_id." >&2
  exit 1
fi

preferences_plist="$(mktemp -t surround-simulator-preferences)"
trap 'rm -f "$preferences_plist"' EXIT

if ! defaults export com.apple.iphonesimulator "$preferences_plist" \
  >/dev/null 2>&1; then
  plutil -create xml1 "$preferences_plist"
fi

ensure_dictionary() {
  local key_path="$1"
  if plutil -extract "$key_path" raw -expect dictionary \
    -o /dev/null "$preferences_plist" 2>/dev/null; then
    return
  fi
  if plutil -type "$key_path" "$preferences_plist" >/dev/null 2>&1; then
    plutil -replace "$key_path" -dictionary "$preferences_plist"
  else
    plutil -insert "$key_path" -dictionary "$preferences_plist"
  fi
}

device_preferences_path="DevicePreferences.${simulator_id}"
keyboard_preference_path="${device_preferences_path}.ConnectHardwareKeyboard"
ensure_dictionary "DevicePreferences"
ensure_dictionary "$device_preferences_path"

# Keep XCTest on the hardware-keyboard path. The UI tests still assert the
# composer-specific keyboard-focus signal and text delivery; this only removes
# the software-keyboard animation that can poison XCTest's quiescence monitor.
if plutil -type "$keyboard_preference_path" "$preferences_plist" \
  >/dev/null 2>&1; then
  plutil -replace "$keyboard_preference_path" -bool true "$preferences_plist"
else
  plutil -insert "$keyboard_preference_path" -bool true "$preferences_plist"
fi

defaults import com.apple.iphonesimulator "$preferences_plist" >/dev/null
defaults export com.apple.iphonesimulator "$preferences_plist" >/dev/null

configured_value="$(
  plutil -extract "$keyboard_preference_path" raw -expect bool \
    -o - "$preferences_plist" 2>/dev/null \
    || true
)"

if [[ "$configured_value" != "true" ]]; then
  echo "Could not enable the hardware keyboard for simulator $simulator_id." >&2
  exit 1
fi

echo "Enabled the hardware keyboard for simulator $simulator_id."
