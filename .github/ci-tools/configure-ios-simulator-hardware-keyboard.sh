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

simulator_record="$(
  xcrun simctl list --json devices available \
    | jq -r --arg simulator_id "$simulator_id" '
        first(
          .devices
          | to_entries[]
          | .key as $runtime
          | .value[]
          | select(
              .udid == $simulator_id and .isAvailable == true
            )
          | [$runtime, .name, .state]
          | @tsv
        ) // empty
      '
)"
if [[ -z "$simulator_record" ]]; then
  echo "No available simulator has UDID $simulator_id." >&2
  exit 1
fi

IFS=$'\t' read -r simulator_runtime simulator_name simulator_state \
  <<< "$simulator_record"

developer_directory="$(xcode-select -p)"
simulator_app="$developer_directory/Applications/Simulator.app"
simulator_executable="$simulator_app/Contents/MacOS/Simulator"
if [[ ! -x "$simulator_executable" ]]; then
  echo "Could not find Simulator.app for the selected Xcode at $simulator_app." >&2
  exit 1
fi

current_simulator_state() {
  xcrun simctl list --json devices available \
    | jq -r --arg simulator_id "$simulator_id" '
        first(
          .devices[][]
          | select(.udid == $simulator_id)
          | .state
        ) // empty
      '
}

# Simulator.app owns ConnectHardwareKeyboard and can cache it independently of
# CoreSimulator. Stop the host before updating the preference so the new
# process starts with the selected device's value.
if pgrep -x Simulator >/dev/null 2>&1; then
  echo "Stopping Simulator.app before changing its keyboard preference."
  pkill -TERM -x Simulator
  for _ in {1..30}; do
    pgrep -x Simulator >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -x Simulator >/dev/null 2>&1; then
    echo "Simulator.app did not stop before keyboard configuration." >&2
    exit 1
  fi
fi

simulator_state="$(current_simulator_state)"

if [[ "$simulator_state" != "Shutdown" ]]; then
  echo "Shutting down $simulator_name before changing its keyboard preference."
  if [[ "$simulator_state" != "Shutting Down" ]]; then
    xcrun simctl shutdown "$simulator_id"
  fi

  for _ in {1..60}; do
    simulator_state="$(current_simulator_state)"
    [[ "$simulator_state" == "Shutdown" ]] && break
    sleep 1
  done
  if [[ "$simulator_state" != "Shutdown" ]]; then
    echo "Simulator $simulator_id did not shut down before configuration." >&2
    exit 1
  fi
fi

preferences_plist="$(mktemp -t surround-simulator-preferences)"
trap 'rm -f "$preferences_plist"' EXIT

if ! defaults export com.apple.iphonesimulator "$preferences_plist" \
  >/dev/null 2>&1; then
  plutil -create xml1 "$preferences_plist"
fi

ensure_dictionary() {
  local key_path="$1"
  local plist_buddy_path=":${key_path//./:}"
  if /usr/libexec/PlistBuddy \
    -c "Print $plist_buddy_path" "$preferences_plist" \
    >/dev/null 2>&1; then
    return
  fi

  /usr/libexec/PlistBuddy \
    -c "Add $plist_buddy_path dict" "$preferences_plist"
}

device_preferences_path="DevicePreferences.${simulator_id}"
keyboard_preference_path="${device_preferences_path}.ConnectHardwareKeyboard"
ensure_dictionary "DevicePreferences"
ensure_dictionary "$device_preferences_path"

# Keep XCTest on the hardware-keyboard path. The UI tests still assert the
# composer-specific keyboard-focus signal and text delivery; this only removes
# the software-keyboard animation that can poison XCTest's quiescence monitor.
keyboard_preference_buddy_path=":${keyboard_preference_path//./:}"
/usr/libexec/PlistBuddy \
  -c "Delete $keyboard_preference_buddy_path" "$preferences_plist" \
  >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
  -c "Add $keyboard_preference_buddy_path bool true" "$preferences_plist"

defaults import com.apple.iphonesimulator "$preferences_plist" >/dev/null
defaults export com.apple.iphonesimulator "$preferences_plist" >/dev/null

verification_key="SurroundHardwareKeyboardVerification"
/usr/libexec/PlistBuddy \
  -c "Delete :$verification_key" "$preferences_plist" \
  >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
  -c "Copy $keyboard_preference_buddy_path :$verification_key" \
  "$preferences_plist"
configured_value="$(
  plutil -extract "$verification_key" raw -expect bool \
    -o - "$preferences_plist" 2>/dev/null \
    || true
)"
/usr/libexec/PlistBuddy \
  -c "Delete :$verification_key" "$preferences_plist"

if [[ "$configured_value" != "true" ]]; then
  echo "Could not enable the hardware keyboard for simulator $simulator_id." >&2
  exit 1
fi

echo "Enabled the hardware keyboard for $simulator_name ($simulator_id)."
echo "Booting $simulator_name on $simulator_runtime with the new preference."
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

echo "Launching Simulator.app for $simulator_name."
open "$simulator_app" --args -CurrentDeviceUDID "$simulator_id"
osascript -e 'tell application id "com.apple.iphonesimulator" to activate' \
  >/dev/null 2>&1 || true

for _ in {1..30}; do
  pgrep -f "$simulator_executable" >/dev/null 2>&1 && break
  sleep 1
done
if ! pgrep -f "$simulator_executable" >/dev/null 2>&1; then
  echo "Simulator.app did not launch for keyboard configuration." >&2
  exit 1
fi

simulator_state="$(current_simulator_state)"
if [[ "$simulator_state" != "Booted" ]]; then
  echo "Simulator $simulator_id did not reach the Booted state." >&2
  exit 1
fi

hardware_keyboard_state=""
for attempt in 1 2; do
  for _ in {1..15}; do
    hardware_keyboard_state="$(
      xcrun simctl notify_get_state \
        "$simulator_id" GSEventHardwareKeyboardAttached \
        2>/dev/null || true
    )"
    if [[ "$hardware_keyboard_state" =~ ^[0-9]+$ ]] \
      && (( (hardware_keyboard_state & 255) != 0 )); then
      break 2
    fi
    sleep 1
  done

  if (( attempt < 2 )); then
    echo "Retrying Simulator.app activation for hardware-keyboard attachment."
    open "$simulator_app" --args -CurrentDeviceUDID "$simulator_id"
    osascript -e 'tell application id "com.apple.iphonesimulator" to activate' \
      >/dev/null 2>&1 || true
  fi
done

if ! [[ "$hardware_keyboard_state" =~ ^[0-9]+$ ]] \
  || (( (hardware_keyboard_state & 255) == 0 )); then
  echo "Warning: the booted simulator did not report an attached hardware keyboard; the XCUI preflight will verify the observable behavior." >&2
fi

echo "Simulator keyboard setup complete: name=$simulator_name state=$simulator_state preference=$configured_value guestState=$hardware_keyboard_state"
