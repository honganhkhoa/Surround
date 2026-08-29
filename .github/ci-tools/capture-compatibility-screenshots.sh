#!/usr/bin/env bash

set -euo pipefail

readonly exit_usage=64
readonly scheme_name="CompatibilityScreenshots"
readonly test_plan_name="CompatibilityScreenshots"
readonly legacy_screenshot_test_identifier="SurroundUITests/CompatibilityScreenshotTests/testCompatibilityScreenshots"
readonly adaptive_screenshot_test_identifier="SurroundUITests/CompatibilityScreenshotTests/testAdaptiveWidgetRegressionScreenshots"
readonly widget_tap_test_identifier="SurroundUITests/CompatibilityScreenshotTests/testWidgetTapTargets"
readonly app_bundle_identifier="com.honganhkhoa.Surround"
readonly ui_test_runner_bundle_identifier="com.honganhkhoa.SurroundUITests.xctrunner"
readonly required_iphone_device_type_identifier="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
readonly required_ipad_device_type_identifier="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB"
readonly widget_fixture_cleanup_launch_argument="--clear-app-store-screenshot-widget-fixture"
readonly simulator_boot_timeout_seconds=180
readonly simulator_command_timeout_seconds=60
readonly status_bar_offset="$(
  date -j -f "%Y-%m-%d %H:%M:%S" "2007-01-09 09:41:00" "+%z"
)"
readonly status_bar_date_time="2007-01-09T09:41:00.000${status_bar_offset:0:3}:${status_bar_offset:3:2}"

usage() {
  cat <<'EOF'
Capture one deterministic Surround compatibility screenshot set.

Usage:
  capture-compatibility-screenshots.sh \
    --output PATH --runtime RUNTIME \
    [--iphone-device NAME] [--ipad-device NAME] \
    [--derived-data PATH] [--source-fingerprint SHA256] \
    [--ephemeral-devices | --reuse-devices]

Options:
  --output PATH             Required new output directory.
  --runtime RUNTIME         Required exact iOS runtime identifier, version, or
                            name (for example 18.0 or iOS 18.0).
  --iphone-device NAME      Defaults to iPhone 16 Pro Max.
  --ipad-device NAME        Defaults to iPad Pro 13-inch (M4).
  --derived-data PATH       Reusable DerivedData directory. It is not deleted.
  --source-fingerprint HEX  Recorded in run-metadata.json.
  --ephemeral-devices       Create clean simulators for this run and delete
                            them during teardown (the default).
  --reuse-devices           Reuse matching installed simulators. This removes
                            Surround and its UI-test runner, and can rearrange
                            Home Screen content on those simulators.
  -h, --help                Show this help.

The output contains one xcresult, exported attachments, 35 normalized iPhone
PNGs, 37 normalized iPad PNGs, an attachment record, a build log, and run
metadata. By default the runner creates isolated simulators and verifies their
deletion during teardown. With --reuse-devices, selected simulators are returned
to their original boot state, locale, and appearance, but app data and Home
Screen layout are not preserved.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

usage_error() {
  echo "error: $*" >&2
  echo >&2
  usage >&2
  exit "$exit_usage"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fail "Required command was not found: $1"
}

strip_trailing_slashes() {
  local path="$1"
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

validate_non_broad_path() {
  local label="$1"
  local path
  path="$(strip_trailing_slashes "$2")"
  [[ -n "$path" ]] || usage_error "${label} must not be empty."
  case "$path" in
    /|.|..)
      usage_error "${label} must identify a dedicated directory, not '${path}'."
      ;;
  esac
}

select_device() {
  local runtime_identifier="$1"
  local device_name="$2"
  local match

  match="$(
    jq -r \
      --arg runtime "$runtime_identifier" \
      --arg name "$device_name" '
        [
          .devices[$runtime][]?
          | select(.isAvailable != false)
          | select(.name == $name)
        ]
        | first
        | if . == null then
            empty
          else
            [
              .udid,
              .name,
              .state,
              .deviceTypeIdentifier
            ]
            | @tsv
          end
      ' <<<"$available_devices_json"
  )"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
    return 0
  fi

  echo "No available simulator named '${device_name}' exists in ${runtime_identifier}." >&2
  echo "Available devices in that runtime:" >&2
  jq -r \
    --arg runtime "$runtime_identifier" \
    '.devices[$runtime][]? | select(.isAvailable != false) | "  \(.name)"' \
    <<<"$available_devices_json" >&2
  return 1
}

restore_signal_traps() {
  if [[ "${cleanup_in_progress:-false}" == true ]]; then
    trap '' INT TERM
  else
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
}

stop_active_timed_command() {
  local command_pid="${active_timed_command_pid:-}"
  local attempt

  [[ -n "$command_pid" ]] || return 0
  trap '' INT TERM
  if kill -0 "$command_pid" 2>/dev/null; then
    kill -TERM "$command_pid" 2>/dev/null || true
    for attempt in 1 2 3 4 5; do
      kill -0 "$command_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$command_pid" 2>/dev/null; then
      kill -KILL "$command_pid" 2>/dev/null || true
    fi
  fi
  wait "$command_pid" 2>/dev/null || true
  active_timed_command_pid=""
  restore_signal_traps
}

run_timed_command() {
  local timeout_seconds="$1"
  local description="$2"
  shift 2
  local deadline
  local command_pid
  local command_exit_code=0

  trap '' INT TERM
  "$@" &
  command_pid=$!
  active_timed_command_pid="$command_pid"
  restore_signal_traps
  deadline="$((SECONDS + timeout_seconds))"

  while kill -0 "$command_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      echo "warning: Timed out after ${timeout_seconds}s while ${description}." >&2
      stop_active_timed_command
      return 124
    fi
    sleep 1
  done

  wait "$command_pid" || command_exit_code=$?
  active_timed_command_pid=""
  return "$command_exit_code"
}

wait_for_device_boot() {
  local device_id="$1"
  local device_name="$2"

  run_timed_command \
    "$simulator_boot_timeout_seconds" \
    "waiting for ${device_name} (${device_id}) to boot" \
    xcrun simctl bootstatus "$device_id" -b
}

start_clean_boot() {
  local device_id="$1"
  local device_name="$2"

  run_timed_command \
    "$simulator_command_timeout_seconds" \
    "shutting down ${device_name} (${device_id})" \
    xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
  run_timed_command \
    "$simulator_command_timeout_seconds" \
    "starting ${device_name} (${device_id})" \
    xcrun simctl boot "$device_id" \
    || return 1
  wait_for_device_boot "$device_id" "$device_name"
}

boot_device() {
  local device_id="$1"
  local device_name="$2"
  local initial_boot_started=true

  if [[ "$3" != "Booted" ]]; then
    echo "Booting ${device_name} (${device_id})..."
    run_timed_command \
      "$simulator_command_timeout_seconds" \
      "starting ${device_name} (${device_id})" \
      xcrun simctl boot "$device_id" \
      || initial_boot_started=false
  else
    echo "${device_name} (${device_id}) is already booted."
  fi

  if [[ "$initial_boot_started" == true ]] \
    && wait_for_device_boot "$device_id" "$device_name"; then
    return 0
  fi

  echo "warning: Retrying one clean boot for ${device_name} (${device_id})." >&2
  start_clean_boot "$device_id" "$device_name"
}

pin_status_bar() {
  local device_id="$1"
  xcrun simctl status_bar "$device_id" override \
    --time "$status_bar_date_time" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4
}

read_device_languages() {
  local device_id="$1"
  xcrun simctl spawn "$device_id" \
    defaults read NSGlobalDomain AppleLanguages \
    | awk -F '"' '/^[[:space:]]*"/ { print $2 }'
}

read_device_locale() {
  local device_id="$1"
  xcrun simctl spawn "$device_id" \
    defaults read NSGlobalDomain AppleLocale
}

write_device_locale() {
  local device_id="$1"
  local locale="$2"
  shift 2
  (( $# > 0 )) || fail "At least one simulator language is required."

  xcrun simctl spawn "$device_id" \
    defaults write NSGlobalDomain AppleLanguages -array "$@"
  xcrun simctl spawn "$device_id" \
    defaults write NSGlobalDomain AppleLocale "$locale"
}

restart_device() {
  local device_id="$1"
  local device_name="${2:-$device_id}"
  local initial_boot_started=true

  run_timed_command \
    "$simulator_command_timeout_seconds" \
    "shutting down ${device_name} (${device_id})" \
    xcrun simctl shutdown "$device_id" \
    || initial_boot_started=false
  if [[ "$initial_boot_started" == true ]]; then
    run_timed_command \
      "$simulator_command_timeout_seconds" \
      "starting ${device_name} (${device_id})" \
      xcrun simctl boot "$device_id" \
      || initial_boot_started=false
  fi
  if [[ "$initial_boot_started" == true ]] \
    && wait_for_device_boot "$device_id" "$device_name"; then
    return 0
  fi

  echo "warning: Retrying one clean boot for ${device_name} (${device_id})." >&2
  start_clean_boot "$device_id" "$device_name"
}

uninstall_and_verify_absent() {
  local device_id="$1"
  local bundle_identifier="$2"

  xcrun simctl uninstall \
    "$device_id" \
    "$bundle_identifier" >/dev/null 2>&1 || true
  if xcrun simctl get_app_container \
    "$device_id" \
    "$bundle_identifier" \
    app >/dev/null 2>&1; then
    fail "Could not remove stale app container ${bundle_identifier} from ${device_id}."
  fi
}

iphone_id=""
ipad_id=""
iphone_device_type_identifier=""
ipad_device_type_identifier=""
iphone_initial_state=""
ipad_initial_state=""
iphone_initial_appearance=""
ipad_initial_appearance=""
iphone_initial_locale=""
ipad_initial_locale=""
iphone_initial_languages=()
ipad_initial_languages=()
iphone_locale_changed=false
ipad_locale_changed=false
simulators_ready=false
ephemeral_devices=true
active_timed_command_pid=""
cleanup_in_progress=false

restore_simulators() {
  local saved_exit_code=$?
  local device_id
  local device_inventory_path
  local cleanup_failed=false
  trap - EXIT
  set +e
  cleanup_in_progress=true
  trap '' INT TERM

  stop_active_timed_command

  if [[ "$simulators_ready" == true && "$ephemeral_devices" != true ]]; then
    for device_id in "$iphone_id" "$ipad_id"; do
      if xcrun simctl launch \
        --terminate-running-process \
        "$device_id" \
        "$app_bundle_identifier" \
        "$widget_fixture_cleanup_launch_argument" >/dev/null 2>&1; then
        xcrun simctl terminate \
          "$device_id" \
          "$app_bundle_identifier" >/dev/null 2>&1
      fi
      xcrun simctl status_bar "$device_id" clear >/dev/null 2>&1
    done
    if [[ "$iphone_locale_changed" == true ]]; then
      write_device_locale \
        "$iphone_id" \
        "$iphone_initial_locale" \
        "${iphone_initial_languages[@]}" >/dev/null 2>&1
    fi
    if [[ "$ipad_locale_changed" == true ]]; then
      write_device_locale \
        "$ipad_id" \
        "$ipad_initial_locale" \
        "${ipad_initial_languages[@]}" >/dev/null 2>&1
    fi
    if [[ "$iphone_initial_appearance" == "dark" ]]; then
      xcrun simctl ui "$iphone_id" appearance dark >/dev/null 2>&1
    fi
    if [[ "$ipad_initial_appearance" == "dark" ]]; then
      xcrun simctl ui "$ipad_id" appearance dark >/dev/null 2>&1
    fi
    if [[ "$iphone_initial_state" == "Booted"
          && "$iphone_locale_changed" == true ]]; then
      if ! restart_device "$iphone_id" "$iphone_name" >/dev/null 2>&1; then
        echo "error: Could not restore simulator state for ${iphone_id}." >&2
        cleanup_failed=true
      fi
    elif [[ "$iphone_initial_state" != "Booted" ]]; then
      xcrun simctl shutdown "$iphone_id" >/dev/null 2>&1
    fi
    if [[ "$ipad_initial_state" == "Booted"
          && "$ipad_locale_changed" == true ]]; then
      if ! restart_device "$ipad_id" "$ipad_name" >/dev/null 2>&1; then
        echo "error: Could not restore simulator state for ${ipad_id}." >&2
        cleanup_failed=true
      fi
    elif [[ "$ipad_initial_state" != "Booted" ]]; then
      xcrun simctl shutdown "$ipad_id" >/dev/null 2>&1
    fi
  fi
  if [[ "$ephemeral_devices" == true ]]; then
    for device_id in "$iphone_id" "$ipad_id"; do
      [[ -n "$device_id" ]] || continue
      run_timed_command \
        "$simulator_command_timeout_seconds" \
        "shutting down temporary simulator ${device_id}" \
        xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
      if ! run_timed_command \
        "$simulator_command_timeout_seconds" \
        "deleting temporary simulator ${device_id}" \
        xcrun simctl delete "$device_id" >/dev/null 2>&1; then
        echo "error: Could not delete temporary simulator ${device_id}." >&2
        cleanup_failed=true
        continue
      fi
      device_inventory_path="${output_root}/.simulator-inventory-${device_id}.json"
      if ! run_timed_command \
        "$simulator_command_timeout_seconds" \
        "reading simulator inventory after deleting ${device_id}" \
        xcrun simctl list devices -j >"$device_inventory_path" 2>/dev/null; then
        echo "error: Could not verify deletion of temporary simulator ${device_id}." >&2
        cleanup_failed=true
      elif ! jq -e '
        (.devices | type) == "object"
        and all(.devices[]; type == "array")
        and all(
          .devices[][];
          type == "object" and (.udid | type) == "string"
        )
      ' "$device_inventory_path" >/dev/null; then
        echo "error: Simulator inventory was malformed while verifying deletion of ${device_id}." >&2
        cleanup_failed=true
      elif ! jq -e \
        --arg device_id "$device_id" \
        'all(.devices[][]; .udid != $device_id)' \
        "$device_inventory_path" >/dev/null; then
        echo "error: Temporary simulator ${device_id} still exists after deletion." >&2
        cleanup_failed=true
      fi
      rm -f -- "$device_inventory_path"
    done
  fi

  if [[ "$cleanup_failed" == true && "$saved_exit_code" -eq 0 ]]; then
    exit 1
  fi
  exit "$saved_exit_code"
}

image_property() {
  local property="$1"
  local path="$2"
  sips -g "$property" "$path" 2>/dev/null \
    | awk -v property="$property" \
      '$1 == property ":" { print $2; exit }'
}

validate_png() {
  local png_path="$1"
  local family="$2"
  local stage="$3"
  local format width height has_alpha dimensions

  format="$(image_property format "$png_path")"
  width="$(image_property pixelWidth "$png_path")"
  height="$(image_property pixelHeight "$png_path")"
  has_alpha="$(image_property hasAlpha "$png_path")"

  [[ "$format" == "png" ]] \
    || fail "Screenshot is not a PNG: ${png_path}"
  case "$has_alpha" in
    no|false)
      ;;
    *)
      fail "Screenshot has an alpha channel: ${png_path}"
      ;;
  esac

  dimensions="${width}x${height}"
  case "${family}:${stage}:${dimensions}" in
    iphone:raw:1320x2868|iphone:final:1320x2868)
      ;;
    ipad:raw:2064x2752|ipad:raw:2752x2064|ipad:final:2752x2064)
      ;;
    *)
      fail "Unexpected ${family} ${stage} dimensions ${dimensions}: ${png_path}"
      ;;
  esac
}

output_argument=""
runtime_argument=""
iphone_device_argument="iPhone 16 Pro Max"
ipad_device_argument="iPad Pro 13-inch (M4)"
derived_data_argument=""
source_fingerprint_argument=""

while (( $# > 0 )); do
  case "$1" in
    --output)
      (( $# >= 2 )) || usage_error "--output requires a path."
      output_argument="$2"
      shift 2
      ;;
    --output=*)
      output_argument="${1#*=}"
      shift
      ;;
    --runtime)
      (( $# >= 2 )) || usage_error "--runtime requires a value."
      runtime_argument="$2"
      shift 2
      ;;
    --runtime=*)
      runtime_argument="${1#*=}"
      shift
      ;;
    --iphone-device)
      (( $# >= 2 )) || usage_error "--iphone-device requires a name."
      iphone_device_argument="$2"
      shift 2
      ;;
    --iphone-device=*)
      iphone_device_argument="${1#*=}"
      shift
      ;;
    --ipad-device)
      (( $# >= 2 )) || usage_error "--ipad-device requires a name."
      ipad_device_argument="$2"
      shift 2
      ;;
    --ipad-device=*)
      ipad_device_argument="${1#*=}"
      shift
      ;;
    --derived-data)
      (( $# >= 2 )) || usage_error "--derived-data requires a path."
      derived_data_argument="$2"
      shift 2
      ;;
    --derived-data=*)
      derived_data_argument="${1#*=}"
      shift
      ;;
    --source-fingerprint)
      (( $# >= 2 )) || usage_error "--source-fingerprint requires a value."
      source_fingerprint_argument="$2"
      shift 2
      ;;
    --source-fingerprint=*)
      source_fingerprint_argument="${1#*=}"
      shift
      ;;
    --ephemeral-devices)
      ephemeral_devices=true
      shift
      ;;
    --reuse-devices)
      ephemeral_devices=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$output_argument" ]] || usage_error "--output is required."
[[ -n "$runtime_argument" ]] || usage_error "--runtime is required."
[[ -n "$iphone_device_argument" ]] \
  || usage_error "--iphone-device must not be empty."
[[ -n "$ipad_device_argument" ]] \
  || usage_error "--ipad-device must not be empty."

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "${script_directory}/../.." && pwd -P)"
project_path="${repository_root}/Surround.xcodeproj"
manifest_path="${script_directory}/compatibility-screenshot-scenes.json"
normalizer_source="${script_directory}/normalize-app-store-screenshot.swift"
runtime_helper="${script_directory}/ios-simulator-runtime.sh"

[[ -d "$project_path" ]] \
  || fail "Xcode project was not found: ${project_path}"
[[ -f "$manifest_path" ]] \
  || fail "Scene manifest was not found: ${manifest_path}"
[[ -f "$normalizer_source" ]] \
  || fail "Screenshot normalizer was not found: ${normalizer_source}"
[[ -f "$runtime_helper" ]] \
  || fail "iOS runtime helper was not found: ${runtime_helper}"

source "$runtime_helper"

invocation_directory="$PWD"
if [[ "$output_argument" != /* ]]; then
  output_argument="${invocation_directory}/${output_argument}"
fi
validate_non_broad_path "Output path" "$output_argument"
if [[ -e "$output_argument" || -L "$output_argument" ]]; then
  usage_error "Output path already exists: ${output_argument}"
fi
mkdir -p "$output_argument"
output_root="$(cd "$output_argument" && pwd -P)"

if [[ -z "$derived_data_argument" ]]; then
  derived_data_argument="${repository_root}/.build/CompatibilityScreenshotDerivedData"
elif [[ "$derived_data_argument" != /* ]]; then
  derived_data_argument="${invocation_directory}/${derived_data_argument}"
fi
validate_non_broad_path "DerivedData path" "$derived_data_argument"
if [[ -e "$derived_data_argument" && ! -d "$derived_data_argument" ]]; then
  usage_error "DerivedData path is not a directory: ${derived_data_argument}"
fi
mkdir -p "$derived_data_argument"
derived_data_path="$(cd "$derived_data_argument" && pwd -P)"

for command_name in awk jq sips tee xcodebuild xcrun; do
  require_command "$command_name"
done

jq -e '
  .schemaVersion == 1
  and .locale == "en-US"
  and .appearance == "light"
  and .deviceFamilies.iphone.deviceName == "iPhone 16 Pro Max"
  and .deviceFamilies.iphone.orientation == "portrait"
  and .deviceFamilies.ipad.deviceName == "iPad Pro 13-inch (M4)"
  and .deviceFamilies.ipad.orientation == "landscape"
  and (
    [.deviceFamilies.iphone.scenes[].name]
    == [
      "welcome",
      "home",
      "public-games",
      "game-history",
      "messages-inbox",
      "message-thread",
      "settings",
      "about",
      "thanks",
      "supporter",
      "browser",
      "unsupported-google",
      "active-game-board",
      "game-analysis",
      "zen-mode",
      "game-options",
      "finished-game-playback",
      "public-game-spectator",
      "quick-match",
      "open-challenges",
      "rengo-open-challenges",
      "custom-game",
      "opponent-picker",
      "advanced-time",
      "advanced-rules",
      "waiting-games",
      "preferred-settings",
      "preferred-setting-editor",
      "game-chat",
      "widget-small",
      "widget-medium",
      "widget-large",
      "widget-small-full-capacity",
      "widget-large-one-game",
      "widget-large-three-games"
    ]
  )
  and (
    [.deviceFamilies.ipad.scenes[].name]
    == [
      "welcome",
      "home",
      "public-games",
      "game-history",
      "messages-inbox",
      "message-thread",
      "settings",
      "about",
      "thanks",
      "supporter",
      "browser",
      "unsupported-google",
      "active-game-board",
      "game-analysis",
      "zen-mode",
      "game-options",
      "finished-game-playback",
      "public-game-spectator",
      "quick-match",
      "open-challenges",
      "rengo-open-challenges",
      "custom-game",
      "opponent-picker",
      "advanced-time",
      "advanced-rules",
      "waiting-games",
      "preferred-settings",
      "preferred-setting-editor",
      "widget-small",
      "widget-medium",
      "widget-large",
      "widget-small-full-capacity",
      "widget-large-one-game",
      "widget-large-three-games",
      "widget-extra-large-one-game",
      "widget-extra-large-four-games",
      "widget-extra-large-six-games"
    ]
  )
  and (
    .deviceFamilies[]
    | (.scenes | map(.name) | length)
      == (.scenes | map(.name) | unique | length)
  )
  and (
    [.deviceFamilies[].scenes[].kind]
    | all(. == "native" or . == "widget")
  )
  and (
    [
      .deviceFamilies.iphone.scenes[],
      .deviceFamilies.ipad.scenes[]
    ]
    | map(select(.kind == "widget"))
    | all(
        (
          (
            .name == "widget-small"
            or .name == "widget-small-full-capacity"
          )
          and .widgetFamily == "systemSmall"
        )
        or (
          .name == "widget-medium"
          and .widgetFamily == "systemMedium"
        )
        or (
          (
            .name == "widget-large"
            or .name == "widget-large-one-game"
            or .name == "widget-large-three-games"
          )
          and .widgetFamily == "systemLarge"
        )
        or (
          (
            .name == "widget-extra-large-one-game"
            or .name == "widget-extra-large-four-games"
            or .name == "widget-extra-large-six-games"
          )
          and .widgetFamily == "systemExtraLarge"
        )
      )
  )
  and (
    [
      .deviceFamilies.iphone.scenes[],
      .deviceFamilies.ipad.scenes[]
    ]
    | map(select(.kind == "native"))
    | all(has("widgetFamily") | not)
  )
' "$manifest_path" >/dev/null \
  || fail "The compatibility scene manifest is invalid."

iphone_scenes=()
while IFS= read -r scene; do
  iphone_scenes+=("$scene")
done < <(jq -r '.deviceFamilies.iphone.scenes[].name' "$manifest_path")

ipad_scenes=()
while IFS= read -r scene; do
  ipad_scenes+=("$scene")
done < <(jq -r '.deviceFamilies.ipad.scenes[].name' "$manifest_path")

expected_iphone_scenes_json="$(
  jq -c '.deviceFamilies.iphone.scenes | map(.name)' "$manifest_path"
)"
expected_ipad_scenes_json="$(
  jq -c '.deviceFamilies.ipad.scenes | map(.name)' "$manifest_path"
)"

normalizer_build_path="${derived_data_path}/CompatibilityScreenshotTools"
normalizer_module_cache="${normalizer_build_path}/ModuleCache"
normalizer_path="${normalizer_build_path}/normalize-app-store-screenshot"
mkdir -p "$normalizer_module_cache"
echo "Building the screenshot orientation normalizer..."
xcrun swiftc \
  -module-cache-path "$normalizer_module_cache" \
  "$normalizer_source" \
  -o "$normalizer_path"

xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
xcode_major_version="${xcode_version%%.*}"
if ! [[ "$xcode_major_version" =~ ^[0-9]+$ ]] \
  || (( xcode_major_version < 26 )); then
  fail "Xcode 26 or newer is required; selected Xcode is ${xcode_version:-unknown}."
fi

runtime_line="$(resolve_available_ios_runtime "$runtime_argument")"
[[ -n "$runtime_line" ]] || {
  xcrun simctl list runtimes >&2
  fail "No available iOS runtime matches '${runtime_argument}'."
}
IFS=$'\t' read -r runtime_identifier runtime_version runtime_name \
  <<<"$runtime_line"

trap restore_simulators EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$ephemeral_devices" == true ]]; then
  iphone_id="$(
    xcrun simctl create \
      "$iphone_device_argument" \
      "$required_iphone_device_type_identifier" \
      "$runtime_identifier"
  )"
  [[ -n "$iphone_id" ]] \
    || fail "Could not create the isolated iPhone simulator."
  ipad_id="$(
    xcrun simctl create \
      "$ipad_device_argument" \
      "$required_ipad_device_type_identifier" \
      "$runtime_identifier"
  )"
  [[ -n "$ipad_id" ]] \
    || fail "Could not create the isolated iPad simulator."
  iphone_name="$iphone_device_argument"
  ipad_name="$ipad_device_argument"
  iphone_initial_state="Shutdown"
  ipad_initial_state="Shutdown"
  iphone_device_type_identifier="$required_iphone_device_type_identifier"
  ipad_device_type_identifier="$required_ipad_device_type_identifier"
else
  available_devices_json="$(xcrun simctl list --json devices available)"
  iphone_line="$(
    select_device "$runtime_identifier" "$iphone_device_argument"
  )" || exit 1
  ipad_line="$(
    select_device "$runtime_identifier" "$ipad_device_argument"
  )" || exit 1
  IFS=$'\t' read -r \
    iphone_id \
    iphone_name \
    iphone_initial_state \
    iphone_device_type_identifier \
    <<<"$iphone_line"
  IFS=$'\t' read -r \
    ipad_id \
    ipad_name \
    ipad_initial_state \
    ipad_device_type_identifier \
    <<<"$ipad_line"
fi
[[ "$iphone_id" != "$ipad_id" ]] \
  || fail "The iPhone and iPad destinations have the same identifier."
[[ "$iphone_name" == "$iphone_device_argument" ]] \
  || fail "Selected iPhone profile '${iphone_name}' does not exactly match '${iphone_device_argument}'."
[[ "$ipad_name" == "$ipad_device_argument" ]] \
  || fail "Selected iPad profile '${ipad_name}' does not exactly match '${ipad_device_argument}'."
[[ -n "$iphone_device_type_identifier" ]] \
  || fail "The selected iPhone has no device type identifier."
[[ -n "$ipad_device_type_identifier" ]] \
  || fail "The selected iPad has no device type identifier."
if [[ "$iphone_device_argument" == "iPhone 16 Pro Max" ]]; then
  [[ "$iphone_device_type_identifier" == "$required_iphone_device_type_identifier" ]] \
    || fail "The selected iPhone 16 Pro Max has device type '${iphone_device_type_identifier}', expected '${required_iphone_device_type_identifier}'."
fi
if [[ "$ipad_device_argument" == "iPad Pro 13-inch (M4)" ]]; then
  [[ "$ipad_device_type_identifier" == "$required_ipad_device_type_identifier" ]] \
    || fail "The selected iPad Pro 13-inch (M4) has device type '${ipad_device_type_identifier}', expected '${required_ipad_device_type_identifier}'."
fi

echo "Using ${runtime_name} (${runtime_identifier})."
echo "Selected iPhone: ${iphone_name} (${iphone_id})"
echo "Selected iPad:   ${ipad_name} (${ipad_id})"

simulators_ready=true
boot_device "$iphone_id" "$iphone_name" "$iphone_initial_state" \
  || fail "Could not boot ${iphone_name} (${iphone_id}) after one retry."
boot_device "$ipad_id" "$ipad_name" "$ipad_initial_state" \
  || fail "Could not boot ${ipad_name} (${ipad_id}) after one retry."
while IFS= read -r language; do
  iphone_initial_languages+=("$language")
done < <(read_device_languages "$iphone_id")
while IFS= read -r language; do
  ipad_initial_languages+=("$language")
done < <(read_device_languages "$ipad_id")
iphone_initial_locale="$(read_device_locale "$iphone_id")"
ipad_initial_locale="$(read_device_locale "$ipad_id")"
(( ${#iphone_initial_languages[@]} > 0 )) \
  || fail "Could not determine the iPhone simulator languages."
(( ${#ipad_initial_languages[@]} > 0 )) \
  || fail "Could not determine the iPad simulator languages."
[[ -n "$iphone_initial_locale" ]] \
  || fail "Could not determine the iPhone simulator locale."
[[ -n "$ipad_initial_locale" ]] \
  || fail "Could not determine the iPad simulator locale."
if [[ "${iphone_initial_languages[0]}" != "en-US"
      || "$iphone_initial_locale" != "en_US" ]]; then
  write_device_locale "$iphone_id" "en_US" "en-US"
  iphone_locale_changed=true
fi
if [[ "${ipad_initial_languages[0]}" != "en-US"
      || "$ipad_initial_locale" != "en_US" ]]; then
  write_device_locale "$ipad_id" "en_US" "en-US"
  ipad_locale_changed=true
fi
if [[ "$iphone_locale_changed" == true ]]; then
  restart_device "$iphone_id" "$iphone_name" \
    || fail "Could not restart ${iphone_name} (${iphone_id}) after one retry."
fi
if [[ "$ipad_locale_changed" == true ]]; then
  restart_device "$ipad_id" "$ipad_name" \
    || fail "Could not restart ${ipad_name} (${ipad_id}) after one retry."
fi
iphone_initial_appearance="$(xcrun simctl ui "$iphone_id" appearance)"
ipad_initial_appearance="$(xcrun simctl ui "$ipad_id" appearance)"
case "$iphone_initial_appearance" in
  light|dark)
    ;;
  *)
    fail "Could not determine the iPhone simulator appearance."
    ;;
esac
case "$ipad_initial_appearance" in
  light|dark)
    ;;
  *)
    fail "Could not determine the iPad simulator appearance."
    ;;
esac
xcrun simctl ui "$iphone_id" appearance light
xcrun simctl ui "$ipad_id" appearance light
pin_status_bar "$iphone_id"
pin_status_bar "$ipad_id"

for device_id in "$iphone_id" "$ipad_id"; do
  uninstall_and_verify_absent "$device_id" "$app_bundle_identifier"
  uninstall_and_verify_absent \
    "$device_id" \
    "$ui_test_runner_bundle_identifier"
done

result_bundle_path="${output_root}/CompatibilityScreenshots.xcresult"
raw_attachments_path="${output_root}/attachments"
screenshots_path="${output_root}/screenshots"
xcodebuild_log_path="${output_root}/xcodebuild.log"
records_path="${output_root}/screenshot-attachments.tsv"
metadata_path="${output_root}/run-metadata.json"

echo "Running compatibility screenshots and physical widget taps on iPhone and iPad..."
set -o pipefail
xcodebuild test \
  -project "$project_path" \
  -scheme "$scheme_name" \
  -testPlan "$test_plan_name" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${iphone_id}" \
  -destination "platform=iOS Simulator,id=${ipad_id}" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  -parallel-testing-enabled NO \
  -only-test-configuration "en-US" \
  "-only-testing:${legacy_screenshot_test_identifier}" \
  "-only-testing:${adaptive_screenshot_test_identifier}" \
  "-only-testing:${widget_tap_test_identifier}" \
  2>&1 | tee "$xcodebuild_log_path"

echo "Exporting XCTest attachments..."
xcrun xcresulttool export attachments \
  --path "$result_bundle_path" \
  --output-path "$raw_attachments_path"

attachment_manifest="${raw_attachments_path}/manifest.json"
[[ -f "$attachment_manifest" ]] \
  || fail "xcresulttool did not produce ${attachment_manifest}."
jq -e 'type == "array"' "$attachment_manifest" >/dev/null \
  || fail "Unexpected xcresulttool attachment manifest shape."

jq -r \
  --argjson iphone_scenes "$expected_iphone_scenes_json" \
  --argjson ipad_scenes "$expected_ipad_scenes_json" \
  --arg legacy_test \
    "CompatibilityScreenshotTests/testCompatibilityScreenshots" \
  --arg adaptive_test \
    "CompatibilityScreenshotTests/testAdaptiveWidgetRegressionScreenshots" '
    ($iphone_scenes + $ipad_scenes | unique) as $recognized_scenes
    |
    .[]
    | .testIdentifier as $test_identifier
    | select(
        ($test_identifier | contains($legacy_test))
        or ($test_identifier | contains($adaptive_test))
      )
    | .attachments[]
    | .suggestedHumanReadableName as $suggested_name
    | (
        $recognized_scenes
        | map(
            . as $candidate
            | select(
                $suggested_name == ($candidate + ".png")
                or ($suggested_name | startswith($candidate + "_"))
              )
          )
        | first
      ) as $scene
    | select($scene != null)
    | [
        .configurationName,
        .deviceId,
        .deviceName,
        $scene,
        .exportedFileName
      ]
    | @tsv
  ' "$attachment_manifest" >"$records_path"

expected_total="$(( ${#iphone_scenes[@]} + ${#ipad_scenes[@]} ))"
actual_total="$(
  awk 'NF > 0 { count += 1 } END { print count + 0 }' "$records_path"
)"
[[ "$actual_total" -eq "$expected_total" ]] \
  || fail "Expected ${expected_total} screenshots, found ${actual_total}."

for destination_id in "$iphone_id" "$ipad_id"; do
  if [[ "$destination_id" == "$iphone_id" ]]; then
    expected_count="${#iphone_scenes[@]}"
  else
    expected_count="${#ipad_scenes[@]}"
  fi
  actual_count="$(
    awk -F '\t' -v id="$destination_id" '
      $2 == id { count += 1 }
      END { print count + 0 }
    ' "$records_path"
  )"
  [[ "$actual_count" -eq "$expected_count" ]] \
    || fail "Expected ${expected_count} screenshots from ${destination_id}, found ${actual_count}."
done

mkdir -p "${screenshots_path}/iphone" "${screenshots_path}/ipad"
while IFS=$'\t' read -r configuration device_id device_name scene exported_file; do
  [[ -n "$configuration" ]] || continue
  [[ "$configuration" == "en-US" ]] \
    || fail "Unexpected test configuration '${configuration}'."

  case "$device_id" in
    "$iphone_id")
      family="iphone"
      allowed_scenes_json="$expected_iphone_scenes_json"
      ;;
    "$ipad_id")
      family="ipad"
      allowed_scenes_json="$expected_ipad_scenes_json"
      ;;
    *)
      fail "Screenshot came from unexpected device ${device_name} (${device_id})."
      ;;
  esac
  jq -en \
    --arg scene "$scene" \
    --argjson scenes "$allowed_scenes_json" \
    '$scenes | index($scene) != null' >/dev/null \
    || fail "Unexpected ${family} screenshot '${scene}'."

  source_path="${raw_attachments_path}/${exported_file}"
  destination_path="${screenshots_path}/${family}/${scene}.png"
  [[ -f "$source_path" ]] \
    || fail "Exported attachment is missing: ${source_path}"
  [[ ! -e "$destination_path" ]] \
    || fail "Duplicate screenshot: ${family}/${scene}.png"

  validate_png "$source_path" "$family" raw
  "$normalizer_path" "$source_path" "$destination_path"
  validate_png "$destination_path" "$family" final
  "$normalizer_path" --validate-neutral "$destination_path" >/dev/null
done <"$records_path"

for family in iphone ipad; do
  if [[ "$family" == "iphone" ]]; then
    family_scenes=("${iphone_scenes[@]}")
  else
    family_scenes=("${ipad_scenes[@]}")
  fi
  for scene in "${family_scenes[@]}"; do
    [[ -f "${screenshots_path}/${family}/${scene}.png" ]] \
      || fail "Missing screenshot: ${family}/${scene}.png"
  done
  shopt -s nullglob
  family_files=("${screenshots_path}/${family}"/*.png)
  shopt -u nullglob
  [[ "${#family_files[@]}" -eq "${#family_scenes[@]}" ]] \
    || fail "Unexpected PNG count for ${family}: ${#family_files[@]}"
done

jq -n \
  --arg generatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg sourceFingerprint "$source_fingerprint_argument" \
  --arg xcodeVersion "$xcode_version" \
  --arg runtimeName "$runtime_name" \
  --arg runtimeVersion "$runtime_version" \
  --arg runtimeIdentifier "$runtime_identifier" \
  --arg iphoneName "$iphone_name" \
  --arg iphoneId "$iphone_id" \
  --arg iphoneDeviceTypeIdentifier "$iphone_device_type_identifier" \
  --arg ipadName "$ipad_name" \
  --arg ipadId "$ipad_id" \
  --arg ipadDeviceTypeIdentifier "$ipad_device_type_identifier" \
  --argjson ephemeralDevices "$ephemeral_devices" \
  --arg resultBundle "$result_bundle_path" \
  --slurpfile sceneManifest "$manifest_path" '
    {
      generatedAt: $generatedAt,
      sourceFingerprint: $sourceFingerprint,
      xcodeVersion: $xcodeVersion,
      runtime: {
        name: $runtimeName,
        version: $runtimeVersion,
        identifier: $runtimeIdentifier
      },
      locale: "en-US",
      appearance: "light",
      widgetRenderingMode: "fullColor",
      ephemeralDevices: $ephemeralDevices,
      statusBarTime: "09:41",
      devices: {
        iphone: {
          name: $iphoneName,
          id: $iphoneId,
          deviceTypeIdentifier: $iphoneDeviceTypeIdentifier,
          orientation: "portrait",
          pixelDimensions: "1320x2868"
        },
        ipad: {
          name: $ipadName,
          id: $ipadId,
          deviceTypeIdentifier: $ipadDeviceTypeIdentifier,
          orientation: "landscape",
          pixelDimensions: "2752x2064"
        }
      },
      sceneManifest: $sceneManifest[0],
      screenshotCount: (
        ($sceneManifest[0].deviceFamilies.iphone.scenes | length)
        + ($sceneManifest[0].deviceFamilies.ipad.scenes | length)
      ),
      resultBundle: $resultBundle
    }
  ' >"$metadata_path"

echo
echo "Captured and validated ${actual_total} compatibility screenshots."
echo "Screenshots: ${screenshots_path}"
echo "Metadata:    ${metadata_path}"
echo "Result:      ${result_bundle_path}"
