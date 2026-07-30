#!/usr/bin/env bash

set -euo pipefail

readonly exit_usage=64
readonly scheme_name="AppStoreScreenshots"
readonly test_plan_name="AppStoreScreenshots"
readonly test_identifier="SurroundUITests/AppStoreScreenshotTests/testAppStoreScreenshots"
readonly app_bundle_identifier="com.honganhkhoa.Surround"
readonly widget_fixture_cleanup_launch_argument="--clear-app-store-screenshot-widget-fixture"
readonly status_bar_offset="$(
  date -j -f "%Y-%m-%d %H:%M:%S" "2007-01-09 09:41:00" "+%z"
)"
readonly status_bar_date_time="2007-01-09T09:41:00.000${status_bar_offset:0:3}:${status_bar_offset:3:2}"

readonly -a expected_locales=(
  "en-US"
  "fr-FR"
  "ja-JP"
  "vi-VN"
)

readonly -a expected_iphone_scenes=(
  "01-game-board"
  "02-active-games"
  "03-game-chat"
  "04-open-challenges"
  "05-game-analysis"
  "06-zen-mode"
  "07-preferred-settings"
  "08-public-games"
  "09-game-board-dark"
  "10-home-screen-widget"
)

readonly -a expected_ipad_scenes=(
  "01-game-board"
  "02-active-games"
  "03-game-analysis"
  "04-zen-mode"
  "05-game-board-dark"
  "06-public-games"
  "07-quick-match"
  "08-open-challenges"
  "09-preferred-settings"
  "10-home-screen-widget"
)

readonly -a preferred_iphone_names=(
  "iPhone 17 Pro Max"
  "iPhone 16 Pro Max"
  "iPhone Air"
  "iPhone 16 Plus"
  "iPhone 15 Pro Max"
  "iPhone 15 Plus"
  "iPhone 14 Pro Max"
)

readonly -a preferred_ipad_names=(
  "iPad Pro 13-inch (M5)"
  "iPad Pro 13-inch (M4)"
  "iPad Air 13-inch (M4)"
  "iPad Air 13-inch (M3)"
  "iPad Air 13-inch (M2)"
  "iPad Pro (12.9-inch) (6th generation)"
  "iPad Pro (12.9-inch) (5th generation)"
  "iPad Pro (12.9-inch) (4th generation)"
  "iPad Pro (12.9-inch) (3rd generation)"
)

usage() {
  cat <<'EOF'
Capture deterministic App Store screenshots with Xcode's native UI-test tools.

Usage:
  capture-app-store-screenshots.sh --output PATH [--derived-data PATH]
                                   [--locale LOCALE]...

Options:
  --output PATH        Required. A new output directory; it must not exist.
  --derived-data PATH  Optional reusable DerivedData directory. Defaults to
                       .build/AppStoreScreenshotDerivedData in this repository.
                       It is never deleted by this script.
  --locale LOCALE      Optional exact test-plan configuration to capture.
                       Repeat to capture multiple locales. Supported values are
                       en-US, fr-FR, ja-JP, and vi-VN. Defaults to all four.
  -h, --help           Show this help.

Environment overrides:
  APP_STORE_IPHONE_DEVICE  Exact name of an available 6.9-inch-bucket iPhone
                           simulator in the selected iOS runtime.
  APP_STORE_IPAD_DEVICE    Exact name of an available 13-inch-bucket iPad
                           simulator in that runtime.
  APP_STORE_IOS_RUNTIME    Exact identifier, version, or name of an available
                           iOS runtime. Defaults to the latest installed one.

The AppStoreScreenshots test plan must contain configurations named en-US,
fr-FR, ja-JP, and vi-VN. For example, pass --locale en-US for an English-only
capture. The UI test must keep exactly ten named screenshot attachments for
iPhone and exactly ten for iPad. Run this command with --help after changing
the scene contract, then review the generated index.html.

The output contains the .xcresult bundle, raw exported attachments, validated
screenshots grouped as screenshots/<locale>/<device-family>/, run metadata,
the xcodebuild log, and an index.html review gallery.

Selected simulators are preserved. On exit, the script removes its App Store
screenshot widget fixture, clears status-bar overrides, and returns any
simulator it booted to the shutdown state. Running it again also clears stale
screenshot data left in a Debug widget by an interrupted capture.
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
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 \
    || fail "Required command was not found: ${command_name}"
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
  local family="$2"
  local override_name="$3"
  shift 3

  local -a candidate_names=("$@")
  local candidate_name
  local match

  if [[ -n "$override_name" ]]; then
    candidate_names=("$override_name")
  fi

  for candidate_name in "${candidate_names[@]}"; do
    match="$(
      jq -r \
        --arg runtime "$runtime_identifier" \
        --arg name "$candidate_name" '
          [
            .devices[$runtime][]?
            | select(.isAvailable != false)
            | select(.name == $name)
          ]
          | first
          | if . == null then empty else [.udid, .name, .state] | @tsv end
        ' <<<"$available_devices_json"
    )"

    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  if [[ -z "$override_name" ]]; then
    match="$(
      jq -r \
        --arg runtime "$runtime_identifier" \
        --arg family "$family" '
          [
            .devices[$runtime][]?
            | select(.isAvailable != false)
            | select(
                if $family == "iPhone" then
                  (
                    .name
                    | test("^iPhone (Air|.*(Pro Max|Plus))$")
                  )
                else
                  (
                    .name
                    | test("^iPad .*(13-inch|12[.]9-inch)")
                  )
                end
              )
          ]
          | first
          | if . == null then empty else [.udid, .name, .state] | @tsv end
        ' <<<"$available_devices_json"
    )"

    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  fi

  if [[ -n "$override_name" ]]; then
    echo "No available ${family} simulator named '${override_name}' exists in ${runtime_identifier}." >&2
  else
    echo "No preferred App Store ${family} simulator exists in ${runtime_identifier}." >&2
  fi

  echo "Available devices in that runtime:" >&2
  jq -r \
    --arg runtime "$runtime_identifier" \
    '.devices[$runtime][]? | select(.isAvailable != false) | "  \(.name)"' \
    <<<"$available_devices_json" >&2
  return 1
}

boot_device() {
  local device_id="$1"
  local device_name="$2"
  local state

  state="$(
    xcrun simctl list --json devices \
      | jq -r --arg id "$device_id" '
          [
            .devices[][]
            | select(.udid == $id)
            | .state
          ]
          | first // empty
        '
  )"

  [[ -n "$state" ]] || fail "Could not read simulator state for ${device_name} (${device_id})."

  if [[ "$state" != "Booted" ]]; then
    echo "Booting ${device_name} (${device_id})..."
    xcrun simctl boot "$device_id"
  else
    echo "${device_name} (${device_id}) is already booted."
  fi

  xcrun simctl bootstatus "$device_id" -b
}

status_bar_device_ids=()
shutdown_device_ids=()
cleanup_device_ids=()

restore_simulators() {
  local saved_exit_code=$?
  local device_id

  trap - EXIT
  set +e

  if (( ${#cleanup_device_ids[@]} > 0 )); then
    for device_id in "${cleanup_device_ids[@]}"; do
      if xcrun simctl launch \
        --terminate-running-process \
        "$device_id" \
        "$app_bundle_identifier" \
        "$widget_fixture_cleanup_launch_argument" >/dev/null 2>&1; then
        if ! xcrun simctl terminate \
          "$device_id" \
          "$app_bundle_identifier" >/dev/null 2>&1; then
          echo "warning: Could not terminate the fixture-cleanup app on ${device_id}." >&2
        fi
      else
        echo "warning: Could not clear the App Store screenshot widget fixture on ${device_id}." >&2
      fi
    done
  fi

  if (( ${#status_bar_device_ids[@]} > 0 )); then
    for device_id in "${status_bar_device_ids[@]}"; do
      if ! xcrun simctl status_bar "$device_id" clear >/dev/null 2>&1; then
        echo "warning: Could not clear the status-bar override for ${device_id}." >&2
      fi
    done
  fi

  if (( ${#shutdown_device_ids[@]} > 0 )); then
    for device_id in "${shutdown_device_ids[@]}"; do
      if ! xcrun simctl shutdown "$device_id" >/dev/null 2>&1; then
        echo "warning: Could not restore the shutdown state for ${device_id}." >&2
      fi
    done
  fi

  exit "$saved_exit_code"
}

pin_status_bar() {
  local device_id="$1"

  status_bar_device_ids+=("$device_id")
  xcrun simctl status_bar "$device_id" override \
    --time "$status_bar_date_time" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4
}

validate_png() {
  local png_path="$1"
  local device_family="$2"
  local validation_stage="${3:-final}"
  local metadata
  local format
  local width
  local height
  local has_alpha
  local dimensions

  metadata="$(
    sips \
      -g format \
      -g pixelWidth \
      -g pixelHeight \
      -g hasAlpha \
      "$png_path"
  )"

  format="$(awk '/^[[:space:]]*format:/ { print $2; exit }' <<<"$metadata")"
  width="$(awk '/^[[:space:]]*pixelWidth:/ { print $2; exit }' <<<"$metadata")"
  height="$(awk '/^[[:space:]]*pixelHeight:/ { print $2; exit }' <<<"$metadata")"
  has_alpha="$(awk '/^[[:space:]]*hasAlpha:/ { print $2; exit }' <<<"$metadata")"

  [[ "$format" == "png" ]] \
    || fail "Attachment is not a PNG: ${png_path} (format: ${format:-unknown})"

  case "$has_alpha" in
    no|false)
      ;;
    *)
      fail "PNG has an alpha channel, which App Store Connect rejects: ${png_path}"
      ;;
  esac

  dimensions="${width}x${height}"
  case "${device_family}:${validation_stage}:${dimensions}" in
    iphone-6.9:raw:1260x2736|iphone-6.9:final:1260x2736|\
    iphone-6.9:raw:1290x2796|iphone-6.9:final:1290x2796|\
    iphone-6.9:raw:1320x2868|iphone-6.9:final:1320x2868)
      ;;
    ipad-13:raw:2064x2752|ipad-13:raw:2048x2732|\
    ipad-13:raw:2752x2064|ipad-13:raw:2732x2048|\
    ipad-13:final:2752x2064|ipad-13:final:2732x2048)
      ;;
    iphone-6.9:*)
      fail "Unexpected iPhone screenshot dimensions or orientation ${dimensions}: ${png_path}"
      ;;
    ipad-13:*)
      fail "Unexpected iPad screenshot dimensions or orientation ${dimensions}: ${png_path}"
      ;;
    *)
      fail "Unknown device family '${device_family}' while validating ${png_path}"
      ;;
  esac

  if [[ "$validation_stage" == "final" ]]; then
    "$screenshot_normalizer_path" --validate-neutral "$png_path" >/dev/null
  fi
}

copy_normalized_screenshot() {
  local source_path="$1"
  local destination_path="$2"
  local device_family="$3"

  case "$device_family" in
    iphone-6.9|ipad-13)
      ;;
    *)
      fail "Unknown device family '${device_family}' while normalizing ${source_path}"
      ;;
  esac

  # XCTest attachments can store display orientation only in image metadata.
  # Bake that orientation into the raster and write neutral metadata so image
  # viewers cannot apply the orientation a second time.
  "$screenshot_normalizer_path" "$source_path" "$destination_path"
}

output_argument=""
derived_data_argument=""
requested_locales=()

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
    --derived-data)
      (( $# >= 2 )) || usage_error "--derived-data requires a path."
      derived_data_argument="$2"
      shift 2
      ;;
    --derived-data=*)
      derived_data_argument="${1#*=}"
      shift
      ;;
    --locale)
      (( $# >= 2 )) || usage_error "--locale requires a test-plan configuration name."
      requested_locales+=("$2")
      shift 2
      ;;
    --locale=*)
      requested_locales+=("${1#*=}")
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

selected_locales=()
if (( ${#requested_locales[@]} == 0 )); then
  selected_locales=("${expected_locales[@]}")
else
  for requested_locale in "${requested_locales[@]}"; do
    locale_is_supported=false
    for expected_locale in "${expected_locales[@]}"; do
      if [[ "$requested_locale" == "$expected_locale" ]]; then
        locale_is_supported=true
        break
      fi
    done

    [[ "$locale_is_supported" == true ]] \
      || usage_error "Unsupported locale '${requested_locale}'. Expected one of: ${expected_locales[*]}."

    if (( ${#selected_locales[@]} > 0 )); then
      for selected_locale in "${selected_locales[@]}"; do
        [[ "$requested_locale" != "$selected_locale" ]] \
          || usage_error "Locale '${requested_locale}' was selected more than once."
      done
    fi
    selected_locales+=("$requested_locale")
  done
fi

[[ "${#expected_iphone_scenes[@]}" -eq 10 ]] \
  || fail "The iPhone App Store scene contract must contain exactly 10 entries."
[[ "${#expected_ipad_scenes[@]}" -eq 10 ]] \
  || fail "The iPad App Store scene contract must contain exactly 10 entries."
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "${script_directory}/../.." && pwd -P)"
project_path="${repository_root}/Surround.xcodeproj"

[[ -d "$project_path" ]] || fail "Xcode project was not found: ${project_path}"

invocation_directory="$PWD"
if [[ "$output_argument" != /* ]]; then
  output_argument="${invocation_directory}/${output_argument}"
fi

validate_non_broad_path "Output path" "$output_argument"

if [[ -e "$output_argument" || -L "$output_argument" ]]; then
  usage_error "Output path already exists; choose a new directory: ${output_argument}"
fi

mkdir -p "$output_argument"
output_root="$(cd "$output_argument" && pwd -P)"

if [[ -z "$derived_data_argument" ]]; then
  derived_data_argument="${repository_root}/.build/AppStoreScreenshotDerivedData"
elif [[ "$derived_data_argument" != /* ]]; then
  derived_data_argument="${invocation_directory}/${derived_data_argument}"
fi

validate_non_broad_path "DerivedData path" "$derived_data_argument"

if [[ -e "$derived_data_argument" && ! -d "$derived_data_argument" ]]; then
  usage_error "DerivedData path exists but is not a directory: ${derived_data_argument}"
fi

mkdir -p "$derived_data_argument"
derived_data_path="$(cd "$derived_data_argument" && pwd -P)"

[[ "$derived_data_path" != "/" ]] \
  || usage_error "DerivedData path must not be the filesystem root."
[[ "$derived_data_path" != "$output_root" ]] \
  || usage_error "DerivedData path must be a child of or separate from the output root."

require_command awk
require_command jq
require_command sips
require_command tee
require_command xcodebuild
require_command xcrun

expected_iphone_scenes_json="$(
  jq -cn --args '$ARGS.positional' "${expected_iphone_scenes[@]}"
)"
expected_ipad_scenes_json="$(
  jq -cn --args '$ARGS.positional' "${expected_ipad_scenes[@]}"
)"
readonly expected_iphone_scenes_json expected_ipad_scenes_json
selected_locales_json="$(jq -cn --args '$ARGS.positional' "${selected_locales[@]}")"

screenshot_normalizer_source="${script_directory}/normalize-app-store-screenshot.swift"
screenshot_normalizer_build_path="${derived_data_path}/AppStoreScreenshotTools"
screenshot_normalizer_module_cache="${screenshot_normalizer_build_path}/ModuleCache"
screenshot_normalizer_path="${screenshot_normalizer_build_path}/normalize-app-store-screenshot"

[[ -f "$screenshot_normalizer_source" ]] \
  || fail "Screenshot orientation normalizer was not found: ${screenshot_normalizer_source}"

mkdir -p "$screenshot_normalizer_module_cache"
echo "Building the screenshot orientation normalizer..."
xcrun swiftc \
  -module-cache-path "$screenshot_normalizer_module_cache" \
  "$screenshot_normalizer_source" \
  -o "$screenshot_normalizer_path"

xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
xcode_major_version="${xcode_version%%.*}"
if ! [[ "$xcode_major_version" =~ ^[0-9]+$ ]] || (( xcode_major_version < 26 )); then
  fail "Xcode 26 or newer is required; selected Xcode is ${xcode_version:-unknown}."
fi

runtime_override="${APP_STORE_IOS_RUNTIME:-}"
runtime_line="$(
  xcrun simctl list --json runtimes \
    | jq -r \
      --arg override "$runtime_override" '
        [
          .runtimes[]
          | select(.isAvailable == true)
          | select(.identifier | contains(".SimRuntime.iOS-"))
          | select(
              $override == ""
              or .identifier == $override
              or .version == $override
              or .name == $override
            )
          | . + {
              versionComponents: (
                .version
                | split(".")
                | map(tonumber)
              )
            }
        ]
        | sort_by(.versionComponents)
        | last
        | if . == null then empty else [.identifier, .version, .name] | @tsv end
      '
)"

[[ -n "$runtime_line" ]] || {
  xcrun simctl list runtimes >&2
  if [[ -n "$runtime_override" ]]; then
    fail "No available iOS simulator runtime matches APP_STORE_IOS_RUNTIME='${runtime_override}'."
  fi
  fail "No available iOS simulator runtime is installed."
}

IFS=$'\t' read -r runtime_identifier runtime_version runtime_name <<<"$runtime_line"
echo "Using ${runtime_name} (${runtime_identifier})."

available_devices_json="$(xcrun simctl list --json devices available)"

iphone_line="$(
  select_device \
    "$runtime_identifier" \
    "iPhone" \
    "${APP_STORE_IPHONE_DEVICE:-}" \
    "${preferred_iphone_names[@]}"
)" || exit 1

ipad_line="$(
  select_device \
    "$runtime_identifier" \
    "iPad" \
    "${APP_STORE_IPAD_DEVICE:-}" \
    "${preferred_ipad_names[@]}"
)" || exit 1

IFS=$'\t' read -r iphone_id iphone_name iphone_initial_state <<<"$iphone_line"
IFS=$'\t' read -r ipad_id ipad_name ipad_initial_state <<<"$ipad_line"

[[ "$iphone_id" != "$ipad_id" ]] \
  || fail "The selected iPhone and iPad destinations unexpectedly have the same identifier."

echo "Selected iPhone: ${iphone_name} (${iphone_id})"
echo "Selected iPad:   ${ipad_name} (${ipad_id})"

cleanup_device_ids=("$iphone_id" "$ipad_id")

if [[ "$iphone_initial_state" != "Booted" ]]; then
  shutdown_device_ids+=("$iphone_id")
fi
if [[ "$ipad_initial_state" != "Booted" ]]; then
  shutdown_device_ids+=("$ipad_id")
fi

trap restore_simulators EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

boot_device "$iphone_id" "$iphone_name"
boot_device "$ipad_id" "$ipad_name"

pin_status_bar "$iphone_id"
pin_status_bar "$ipad_id"

result_bundle_path="${output_root}/AppStoreScreenshots.xcresult"
raw_attachments_path="${output_root}/attachments"
screenshots_path="${output_root}/screenshots"
xcodebuild_log_path="${output_root}/xcodebuild.log"
records_path="${output_root}/screenshot-attachments.tsv"
gallery_path="${output_root}/index.html"
metadata_path="${output_root}/run-metadata.json"

xcodebuild_configuration_arguments=()
for locale in "${selected_locales[@]}"; do
  xcodebuild_configuration_arguments+=(
    -only-test-configuration
    "$locale"
  )
done

echo "Running ${test_identifier} across ${#selected_locales[@]} locale(s) and 2 destinations..."
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
  "${xcodebuild_configuration_arguments[@]}" \
  "-only-testing:${test_identifier}" \
  2>&1 | tee "$xcodebuild_log_path"

echo "Exporting XCTest attachments..."
xcrun xcresulttool export attachments \
  --path "$result_bundle_path" \
  --output-path "$raw_attachments_path"

manifest_path="${raw_attachments_path}/manifest.json"
[[ -f "$manifest_path" ]] \
  || fail "xcresulttool did not produce an attachment manifest: ${manifest_path}"

jq -e 'type == "array"' "$manifest_path" >/dev/null \
  || fail "Unexpected xcresulttool attachment manifest shape."

jq -r \
  --argjson iphone_scenes "$expected_iphone_scenes_json" \
  --argjson ipad_scenes "$expected_ipad_scenes_json" \
  --arg expected_test "AppStoreScreenshotTests/testAppStoreScreenshots" '
    ($iphone_scenes + $ipad_scenes | unique) as $recognized_scenes
    |
    .[]
    | select(.testIdentifier | contains($expected_test))
    | .attachments[]
    | . as $attachment
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
  ' "$manifest_path" >"$records_path"

expected_total="$(( ${#selected_locales[@]} * (${#expected_iphone_scenes[@]} + ${#expected_ipad_scenes[@]}) ))"
actual_total="$(awk 'NF > 0 { count += 1 } END { print count + 0 }' "$records_path")"
[[ "$actual_total" -eq "$expected_total" ]] \
  || fail "Expected ${expected_total} named screenshot attachments, found ${actual_total}. See ${manifest_path}."

for locale in "${selected_locales[@]}"; do
  for device_id in "$iphone_id" "$ipad_id"; do
    if [[ "$device_id" == "$iphone_id" ]]; then
      expected_record_count="${#expected_iphone_scenes[@]}"
    else
      expected_record_count="${#expected_ipad_scenes[@]}"
    fi
    record_count="$(
      awk -F '\t' \
        -v expected_locale="$locale" \
        -v expected_device="$device_id" '
          $1 == expected_locale && $2 == expected_device { count += 1 }
          END { print count + 0 }
        ' "$records_path"
    )"
    [[ "$record_count" -eq "$expected_record_count" ]] \
      || fail "Expected exactly ${expected_record_count} screenshot records for ${locale}/${device_id}, found ${record_count}."
  done
done

mkdir -p "$screenshots_path"

while IFS=$'\t' read -r locale device_id device_name scene exported_file_name; do
  [[ -n "$locale" ]] || continue

  if ! jq -en \
    --arg value "$locale" \
    --argjson values "$selected_locales_json" \
    '$values | index($value) != null' >/dev/null; then
    fail "Unexpected test-plan configuration '${locale}' in the attachment manifest."
  fi

  case "$device_id" in
    "$iphone_id")
      device_family="iphone-6.9"
      allowed_scenes_json="$expected_iphone_scenes_json"
      ;;
    "$ipad_id")
      device_family="ipad-13"
      allowed_scenes_json="$expected_ipad_scenes_json"
      ;;
    *)
      fail "Named screenshot came from an unexpected device: ${device_name} (${device_id})"
      ;;
  esac

  if ! jq -en \
    --arg value "$scene" \
    --argjson values "$allowed_scenes_json" \
    '$values | index($value) != null' >/dev/null; then
    fail "Unexpected ${device_family} screenshot '${scene}' for locale ${locale}."
  fi

  source_attachment="${raw_attachments_path}/${exported_file_name}"
  destination_directory="${screenshots_path}/${locale}/${device_family}"
  destination_path="${destination_directory}/${scene}.png"

  [[ -f "$source_attachment" ]] \
    || fail "Exported attachment is missing: ${source_attachment}"
  [[ ! -e "$destination_path" ]] \
    || fail "Duplicate screenshot for ${locale}/${device_family}/${scene}."

  validate_png "$source_attachment" "$device_family" raw
  mkdir -p "$destination_directory"
  copy_normalized_screenshot "$source_attachment" "$destination_path" "$device_family"
done <"$records_path"

for locale in "${selected_locales[@]}"; do
  for device_family in "iphone-6.9" "ipad-13"; do
    combination_path="${screenshots_path}/${locale}/${device_family}"
    [[ -d "$combination_path" ]] \
      || fail "Missing screenshot directory: ${combination_path}"

    if [[ "$device_family" == "iphone-6.9" ]]; then
      device_scenes=("${expected_iphone_scenes[@]}")
    else
      device_scenes=("${expected_ipad_scenes[@]}")
    fi

    for scene in "${device_scenes[@]}"; do
      screenshot_path="${combination_path}/${scene}.png"
      [[ -f "$screenshot_path" ]] \
        || fail "Missing ordered screenshot: ${locale}/${device_family}/${scene}.png"
      validate_png "$screenshot_path" "$device_family"
    done

    shopt -s nullglob
    combination_files=("${combination_path}"/*.png)
    shopt -u nullglob
    [[ "${#combination_files[@]}" -eq "${#device_scenes[@]}" ]] \
      || fail "Expected exactly ${#device_scenes[@]} output PNGs for ${locale}/${device_family}, found ${#combination_files[@]}."
  done
done

jq -n \
  --arg generatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg xcodeVersion "$xcode_version" \
  --arg runtimeName "$runtime_name" \
  --arg runtimeVersion "$runtime_version" \
  --arg runtimeIdentifier "$runtime_identifier" \
  --arg iphoneName "$iphone_name" \
  --arg iphoneId "$iphone_id" \
  --arg ipadName "$ipad_name" \
  --arg ipadId "$ipad_id" \
  --arg resultBundle "$result_bundle_path" \
  --argjson locales "$selected_locales_json" \
  --argjson iphoneScenes "$expected_iphone_scenes_json" \
  --argjson ipadScenes "$expected_ipad_scenes_json" '
    {
      generatedAt: $generatedAt,
      xcodeVersion: $xcodeVersion,
      runtime: {
        name: $runtimeName,
        version: $runtimeVersion,
        identifier: $runtimeIdentifier
      },
      devices: {
        "iphone-6.9": {
          name: $iphoneName,
          id: $iphoneId
        },
        "ipad-13": {
          name: $ipadName,
          id: $ipadId
        }
      },
      locales: $locales,
      scenes: {
        "iphone-6.9": $iphoneScenes,
        "ipad-13": $ipadScenes
      },
      expectedScreenshotCount: (
        ($locales | length)
        * (($iphoneScenes | length) + ($ipadScenes | length))
      ),
      resultBundle: $resultBundle
    }
  ' >"$metadata_path"

{
  printf '%s\n' \
    '<!doctype html>' \
    '<html lang="en">' \
    '<head>' \
    '  <meta charset="utf-8">' \
    '  <meta name="viewport" content="width=device-width, initial-scale=1">' \
    '  <title>Surround App Store screenshots</title>' \
    '  <style>' \
    '    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }' \
    '    body { margin: 0 auto; max-width: 1500px; padding: 32px; }' \
    '    h1, h2, h3 { margin-bottom: 12px; }' \
    '    section { margin: 40px 0; }' \
    '    .grid { display: grid; gap: 20px; align-items: start; }' \
    '    .grid-iphone { grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }' \
    '    .grid-ipad { grid-template-columns: repeat(auto-fit, minmax(min(100%, 480px), 1fr)); }' \
    '    figure { margin: 0; }' \
    '    img { display: block; width: 100%; height: auto; border-radius: 18px; box-shadow: 0 8px 30px rgb(0 0 0 / 18%); }' \
    '    .grid-ipad img { aspect-ratio: 4 / 3; object-fit: contain; }' \
    '    .orientation { font-size: 0.75em; font-weight: normal; opacity: 0.65; }' \
    '    figcaption { margin-top: 8px; font-size: 14px; overflow-wrap: anywhere; }' \
    '  </style>' \
    '</head>' \
    '<body>' \
    '  <h1>Surround App Store screenshots</h1>'

  printf '  <p>iPhone: %s · iPad: %s · iOS %s · Xcode %s</p>\n' \
    "$iphone_name" "$ipad_name" "$runtime_version" "$xcode_version"
  printf '  <p>%s validated screenshots across %s locales.</p>\n' \
    "$actual_total" "${#selected_locales[@]}"

  for locale in "${selected_locales[@]}"; do
    printf '  <section><h2>%s</h2>\n' "$locale"

    for device_family in "iphone-6.9" "ipad-13"; do
      if [[ "$device_family" == "iphone-6.9" ]]; then
        gallery_device_name="$iphone_name"
        gallery_grid_class="grid-iphone"
        gallery_orientation="Portrait"
        gallery_scenes=("${expected_iphone_scenes[@]}")
      else
        gallery_device_name="$ipad_name"
        gallery_grid_class="grid-ipad"
        gallery_orientation="Landscape"
        gallery_scenes=("${expected_ipad_scenes[@]}")
      fi

      printf '    <h3>%s <span class="orientation">· %s</span></h3><div class="grid %s">\n' \
        "$gallery_device_name" "$gallery_orientation" "$gallery_grid_class"
      for scene in "${gallery_scenes[@]}"; do
        relative_path="screenshots/${locale}/${device_family}/${scene}.png"
        printf '      <figure><a href="%s"><img src="%s" loading="lazy" alt="%s %s"></a><figcaption>%s</figcaption></figure>\n' \
          "$relative_path" "$relative_path" "$locale" "$scene" "$scene"
      done
      printf '%s\n' '    </div>'
    done

    printf '%s\n' '  </section>'
  done

  printf '%s\n' \
    '</body>' \
    '</html>'
} >"$gallery_path"

echo
echo "Captured and validated ${actual_total} App Store screenshots."
echo "Screenshots: ${screenshots_path}"
echo "Gallery:     ${gallery_path}"
echo "Result:      ${result_bundle_path}"
