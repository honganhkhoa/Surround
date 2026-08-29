#!/usr/bin/env bash

set -euo pipefail

readonly exit_usage=64
readonly required_iphone_device="iPhone 16 Pro Max"
readonly required_ipad_device="iPad Pro 13-inch (M4)"
readonly required_iphone_device_type_identifier="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
readonly required_ipad_device_type_identifier="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB"

usage() {
  cat <<'EOF'
Capture and compare Surround on iOS/iPadOS 18 and 26.

Usage:
  capture-ios-version-comparison.sh --output PATH [options]

Options:
  --output PATH             Required new output directory.
  --ios-18-runtime VALUE    Identifier, version, or name resolving exactly to
                            iOS 18.0. Default: 18.0.
  --ios-26-runtime VALUE    Identifier, version, or name resolving exactly to
                            iOS 26.0. Default: 26.0.
  --iphone-device NAME      Must be iPhone 16 Pro Max.
  --ipad-device NAME        Must be iPad Pro 13-inch (M4).
  --derived-data PATH       Reusable DerivedData root. Default:
                            .build/CompatibilityScreenshotDerivedData.
  -h, --help                Show this help.

Environment equivalents:
  COMPATIBILITY_IOS18_RUNTIME
  COMPATIBILITY_IOS26_RUNTIME
  COMPATIBILITY_IPHONE_DEVICE
  COMPATIBILITY_IPAD_DEVICE

The output contains 144 normalized originals, 72 labelled lossless comparison
PNGs, comparison.md, index.html, run-metadata.json, and the two source xcresult
runs. All captures are en-US, light/full-color appearance, and use a pinned
9:41 status bar. The command rejects source changes between the two
operating-system runs.
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

repository_fingerprint() {
  (
    cd "$repository_root"
    git rev-parse HEAD
    git diff --no-ext-diff --binary HEAD --
    while IFS= read -r untracked_path; do
      printf 'untracked:%s\n' "$untracked_path"
      shasum -a 256 "$untracked_path"
    done < <(git ls-files --others --exclude-standard)
  ) | shasum -a 256 | awk '{ print $1 }'
}

image_property() {
  local property="$1"
  local path="$2"
  sips -g "$property" "$path" 2>/dev/null \
    | awk -v property="$property" \
      '$1 == property ":" { print $2; exit }'
}

verify_same_dimensions() {
  local left="$1"
  local right="$2"
  local left_width left_height right_width right_height
  left_width="$(image_property pixelWidth "$left")"
  left_height="$(image_property pixelHeight "$left")"
  right_width="$(image_property pixelWidth "$right")"
  right_height="$(image_property pixelHeight "$right")"
  [[ "$left_width" == "$right_width" && "$left_height" == "$right_height" ]] \
    || fail "Source dimensions differ: ${left} is ${left_width}x${left_height}; ${right} is ${right_width}x${right_height}."
}

verify_composite() {
  local path="$1"
  local source="$2"
  local format has_alpha source_width source_height width height
  format="$(image_property format "$path")"
  has_alpha="$(image_property hasAlpha "$path")"
  source_width="$(image_property pixelWidth "$source")"
  source_height="$(image_property pixelHeight "$source")"
  width="$(image_property pixelWidth "$path")"
  height="$(image_property pixelHeight "$path")"

  [[ "$format" == "png" ]] || fail "Composite is not a PNG: ${path}"
  case "$has_alpha" in
    no|false)
      ;;
    *)
      fail "Composite has an alpha channel: ${path}"
      ;;
  esac
  [[ "$width" -eq $(( (source_width * 2) + 24 )) ]] \
    || fail "Composite width is incorrect: ${path}"
  [[ "$height" -eq $(( source_height + 180 )) ]] \
    || fail "Composite height is incorrect: ${path}"
}

output_argument=""
ios18_runtime_argument="${COMPATIBILITY_IOS18_RUNTIME:-18.0}"
ios26_runtime_argument="${COMPATIBILITY_IOS26_RUNTIME:-26.0}"
iphone_device_argument="${COMPATIBILITY_IPHONE_DEVICE:-$required_iphone_device}"
ipad_device_argument="${COMPATIBILITY_IPAD_DEVICE:-$required_ipad_device}"
derived_data_argument=""

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
    --ios-18-runtime)
      (( $# >= 2 )) || usage_error "--ios-18-runtime requires a value."
      ios18_runtime_argument="$2"
      shift 2
      ;;
    --ios-18-runtime=*)
      ios18_runtime_argument="${1#*=}"
      shift
      ;;
    --ios-26-runtime)
      (( $# >= 2 )) || usage_error "--ios-26-runtime requires a value."
      ios26_runtime_argument="$2"
      shift 2
      ;;
    --ios-26-runtime=*)
      ios26_runtime_argument="${1#*=}"
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
[[ -n "$ios18_runtime_argument" ]] \
  || usage_error "--ios-18-runtime must not be empty."
[[ -n "$ios26_runtime_argument" ]] \
  || usage_error "--ios-26-runtime must not be empty."
[[ "$iphone_device_argument" == "$required_iphone_device" ]] \
  || usage_error "--iphone-device must be '${required_iphone_device}'."
[[ "$ipad_device_argument" == "$required_ipad_device" ]] \
  || usage_error "--ipad-device must be '${required_ipad_device}'."

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "${script_directory}/../.." && pwd -P)"
capture_script="${script_directory}/capture-compatibility-screenshots.sh"
composer_source="${script_directory}/compose-ios-version-screenshots.swift"
normalizer_source="${script_directory}/normalize-app-store-screenshot.swift"
scene_manifest="${script_directory}/compatibility-screenshot-scenes.json"
runtime_helper="${script_directory}/ios-simulator-runtime.sh"

[[ -f "$capture_script" ]] \
  || fail "Compatibility capture script was not found: ${capture_script}"
[[ -f "$composer_source" ]] \
  || fail "Comparison compositor was not found: ${composer_source}"
[[ -f "$normalizer_source" ]] \
  || fail "Screenshot normalizer was not found: ${normalizer_source}"
[[ -f "$scene_manifest" ]] \
  || fail "Scene manifest was not found: ${scene_manifest}"
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

if [[ -z "$derived_data_argument" ]]; then
  derived_data_argument="${repository_root}/.build/CompatibilityScreenshotDerivedData"
elif [[ "$derived_data_argument" != /* ]]; then
  derived_data_argument="${invocation_directory}/${derived_data_argument}"
fi
validate_non_broad_path "DerivedData path" "$derived_data_argument"

for command_name in awk git jq shasum sips swift xcrun; do
  require_command "$command_name"
done

expected_iphone_count="$(
  jq -r '.deviceFamilies.iphone.scenes | length' "$scene_manifest"
)"
expected_ipad_count="$(
  jq -r '.deviceFamilies.ipad.scenes | length' "$scene_manifest"
)"
expected_comparison_count="$((
  expected_iphone_count + expected_ipad_count
))"
expected_original_count="$((expected_comparison_count * 2))"

if [[ "$output_argument" == "${repository_root}/"* ]]; then
  relative_output="${output_argument#${repository_root}/}"
  git -C "$repository_root" check-ignore -q "$relative_output" \
    || usage_error "Output inside the repository must be gitignored: ${output_argument}"
fi
if [[ "$derived_data_argument" == "${repository_root}/"* ]]; then
  relative_derived_data="${derived_data_argument#${repository_root}/}"
  git -C "$repository_root" check-ignore -q "$relative_derived_data" \
    || usage_error "DerivedData inside the repository must be gitignored: ${derived_data_argument}"
fi

ios18_runtime_line="$(
  resolve_available_ios_runtime "$ios18_runtime_argument"
)"
[[ -n "$ios18_runtime_line" ]] || {
  xcrun simctl list runtimes >&2
  fail "No available iOS runtime matches '${ios18_runtime_argument}'."
}
IFS=$'\t' read -r \
  ios18_runtime_identifier ios18_runtime_version ios18_runtime_name \
  <<<"$ios18_runtime_line"
[[ "$ios18_runtime_version" == "18.0" ]] || fail \
  "--ios-18-runtime '${ios18_runtime_argument}' resolves to ${ios18_runtime_name} (${ios18_runtime_version}); this comparison requires iOS 18.0."

ios26_runtime_line="$(
  resolve_available_ios_runtime "$ios26_runtime_argument"
)"
[[ -n "$ios26_runtime_line" ]] || {
  xcrun simctl list runtimes >&2
  fail "No available iOS runtime matches '${ios26_runtime_argument}'."
}
IFS=$'\t' read -r \
  ios26_runtime_identifier ios26_runtime_version ios26_runtime_name \
  <<<"$ios26_runtime_line"
[[ "$ios26_runtime_version" == "26.0" ]] || fail \
  "--ios-26-runtime '${ios26_runtime_argument}' resolves to ${ios26_runtime_name} (${ios26_runtime_version}); this comparison requires iOS 26.0."

source_fingerprint="$(repository_fingerprint)"
[[ -n "$source_fingerprint" ]] \
  || fail "Could not fingerprint the repository source state."

mkdir -p \
  "${output_argument}/runs" \
  "${output_argument}/originals/ios-18/iphone" \
  "${output_argument}/originals/ios-18/ipad" \
  "${output_argument}/originals/ios-26/iphone" \
  "${output_argument}/originals/ios-26/ipad" \
  "${output_argument}/comparisons/iphone" \
  "${output_argument}/comparisons/ipad" \
  "${derived_data_argument}/ComparisonTools"
output_root="$(cd "$output_argument" && pwd -P)"
derived_data_root="$(cd "$derived_data_argument" && pwd -P)"

echo "Source fingerprint: ${source_fingerprint}"
echo "Capturing iOS/iPadOS 18..."
bash "$capture_script" \
  --output "${output_root}/runs/ios-18" \
  --runtime "$ios18_runtime_identifier" \
  --iphone-device "$iphone_device_argument" \
  --ipad-device "$ipad_device_argument" \
  --derived-data "${derived_data_root}/ios-18" \
  --source-fingerprint "$source_fingerprint" \
  --ephemeral-devices

[[ "$(repository_fingerprint)" == "$source_fingerprint" ]] \
  || fail "Repository source changed during the iOS 18 capture."

echo "Capturing iOS/iPadOS 26..."
bash "$capture_script" \
  --output "${output_root}/runs/ios-26" \
  --runtime "$ios26_runtime_identifier" \
  --iphone-device "$iphone_device_argument" \
  --ipad-device "$ipad_device_argument" \
  --derived-data "${derived_data_root}/ios-26" \
  --source-fingerprint "$source_fingerprint" \
  --ephemeral-devices

[[ "$(repository_fingerprint)" == "$source_fingerprint" ]] \
  || fail "Repository source changed during the iOS 26 capture."

ios18_metadata="${output_root}/runs/ios-18/run-metadata.json"
ios26_metadata="${output_root}/runs/ios-26/run-metadata.json"
jq -e '
  .runtime.version == "18.0"
  and .screenshotCount == $expected_count
  and .widgetRenderingMode == "fullColor"
  and .ephemeralDevices == true
  and .devices.iphone.name == $iphone_name
  and .devices.ipad.name == $ipad_name
  and .devices.iphone.deviceTypeIdentifier == $iphone_type_identifier
  and .devices.ipad.deviceTypeIdentifier == $ipad_type_identifier
' \
  --arg iphone_name "$iphone_device_argument" \
  --arg ipad_name "$ipad_device_argument" \
  --arg iphone_type_identifier "$required_iphone_device_type_identifier" \
  --arg ipad_type_identifier "$required_ipad_device_type_identifier" \
  --argjson expected_count "$expected_comparison_count" \
  "$ios18_metadata" >/dev/null \
  || fail "The first capture is not a complete iOS 18 run."
jq -e '
  .runtime.version == "26.0"
  and .screenshotCount == $expected_count
  and .widgetRenderingMode == "fullColor"
  and .ephemeralDevices == true
  and .devices.iphone.name == $iphone_name
  and .devices.ipad.name == $ipad_name
  and .devices.iphone.deviceTypeIdentifier == $iphone_type_identifier
  and .devices.ipad.deviceTypeIdentifier == $ipad_type_identifier
' \
  --arg iphone_name "$iphone_device_argument" \
  --arg ipad_name "$ipad_device_argument" \
  --arg iphone_type_identifier "$required_iphone_device_type_identifier" \
  --arg ipad_type_identifier "$required_ipad_device_type_identifier" \
  --argjson expected_count "$expected_comparison_count" \
  "$ios26_metadata" >/dev/null \
  || fail "The second capture is not a complete iOS 26 run."
jq -s -e \
  --arg fingerprint "$source_fingerprint" \
  'length == 2 and all(.[]; .sourceFingerprint == $fingerprint)' \
  "$ios18_metadata" "$ios26_metadata" >/dev/null \
  || fail "A capture metadata fingerprint does not match the source."

for family in iphone ipad; do
  if [[ "$family" == "iphone" ]]; then
    requested_name="$iphone_device_argument"
    required_device_type_identifier="$required_iphone_device_type_identifier"
  else
    requested_name="$ipad_device_argument"
    required_device_type_identifier="$required_ipad_device_type_identifier"
  fi
  ios18_name="$(jq -r --arg family "$family" '.devices[$family].name' "$ios18_metadata")"
  ios26_name="$(jq -r --arg family "$family" '.devices[$family].name' "$ios26_metadata")"
  [[ "$ios18_name" == "$requested_name" ]] \
    || fail "The iOS 18 ${family} profile '${ios18_name}' does not exactly match '${requested_name}'."
  [[ "$ios26_name" == "$requested_name" ]] \
    || fail "The iOS 26 ${family} profile '${ios26_name}' does not exactly match '${requested_name}'."

  ios18_device_type_identifier="$(
    jq -r \
      --arg family "$family" \
      '.devices[$family].deviceTypeIdentifier' \
      "$ios18_metadata"
  )"
  ios26_device_type_identifier="$(
    jq -r \
      --arg family "$family" \
      '.devices[$family].deviceTypeIdentifier' \
      "$ios26_metadata"
  )"
  [[ "$ios18_device_type_identifier" == "$required_device_type_identifier" ]] \
    || fail "The iOS 18 ${family} device type '${ios18_device_type_identifier}' does not exactly match '${required_device_type_identifier}'."
  [[ "$ios26_device_type_identifier" == "$required_device_type_identifier" ]] \
    || fail "The iOS 26 ${family} device type '${ios26_device_type_identifier}' does not exactly match '${required_device_type_identifier}'."
  [[ "$ios18_device_type_identifier" == "$ios26_device_type_identifier" ]] \
    || fail "The ${family} device type identifiers differ: '${ios18_device_type_identifier}' versus '${ios26_device_type_identifier}'."

  cp \
    "${output_root}/runs/ios-18/screenshots/${family}/"*.png \
    "${output_root}/originals/ios-18/${family}/"
  cp \
    "${output_root}/runs/ios-26/screenshots/${family}/"*.png \
    "${output_root}/originals/ios-26/${family}/"
done

composer_module_cache="${derived_data_root}/ComparisonTools/ModuleCache"
composer_path="${derived_data_root}/ComparisonTools/compose-ios-version-screenshots"
normalizer_path="${derived_data_root}/ComparisonTools/normalize-app-store-screenshot"
mkdir -p "$composer_module_cache"
echo "Building the comparison compositor..."
xcrun swiftc \
  -module-cache-path "$composer_module_cache" \
  "$composer_source" \
  -o "$composer_path"
echo "Building the screenshot orientation validator..."
xcrun swiftc \
  -module-cache-path "$composer_module_cache" \
  "$normalizer_source" \
  -o "$normalizer_path"

ios18_version="$(jq -r '.runtime.version' "$ios18_metadata")"
ios26_version="$(jq -r '.runtime.version' "$ios26_metadata")"
comparison_records="${output_root}/comparison-files.tsv"
: >"$comparison_records"

for family in iphone ipad; do
  while IFS=$'\t' read -r scene kind widget_family; do
    left_path="${output_root}/originals/ios-18/${family}/${scene}.png"
    right_path="${output_root}/originals/ios-26/${family}/${scene}.png"
    composite_path="${output_root}/comparisons/${family}/${scene}.png"
    [[ -f "$left_path" ]] \
      || fail "Missing iOS 18 original: ${family}/${scene}.png"
    [[ -f "$right_path" ]] \
      || fail "Missing iOS 26 original: ${family}/${scene}.png"
    verify_same_dimensions "$left_path" "$right_path"

    if [[ "$family" == "iphone" ]]; then
      left_label="iOS ${ios18_version}"
      right_label="iOS ${ios26_version}"
    else
      left_label="iPadOS ${ios18_version}"
      right_label="iPadOS ${ios26_version}"
    fi
    "$composer_path" \
      --left "$left_path" \
      --right "$right_path" \
      --output "$composite_path" \
      --left-label "$left_label" \
      --right-label "$right_label" \
      --title "$scene"
    verify_composite "$composite_path" "$left_path"
    "$normalizer_path" --validate-neutral "$composite_path" >/dev/null

    printf '%s\t%s\t%s\t%s\n' \
      "$family" "$scene" "$kind" "$widget_family" \
      >>"$comparison_records"
  done < <(
    jq -r \
      --arg family "$family" '
        .deviceFamilies[$family].scenes[]
        | [.name, .kind, (.widgetFamily // "")]
        | @tsv
      ' "$scene_manifest"
  )
done

comparison_count="$(
  awk 'NF > 0 { count += 1 } END { print count + 0 }' \
    "$comparison_records"
)"
[[ "$comparison_count" -eq "$expected_comparison_count" ]] \
  || fail "Expected ${expected_comparison_count} comparison PNGs, produced ${comparison_count}."

for family in iphone ipad; do
  shopt -s nullglob
  ios18_files=("${output_root}/originals/ios-18/${family}"/*.png)
  ios26_files=("${output_root}/originals/ios-26/${family}"/*.png)
  comparison_files=("${output_root}/comparisons/${family}"/*.png)
  shopt -u nullglob
  if [[ "$family" == "iphone" ]]; then
    expected_family_count="$expected_iphone_count"
  else
    expected_family_count="$expected_ipad_count"
  fi
  [[ "${#ios18_files[@]}" -eq "$expected_family_count" ]] \
    || fail "Unexpected iOS 18 ${family} original count."
  [[ "${#ios26_files[@]}" -eq "$expected_family_count" ]] \
    || fail "Unexpected iOS 26 ${family} original count."
  [[ "${#comparison_files[@]}" -eq "$expected_family_count" ]] \
    || fail "Unexpected ${family} comparison count."
done

metadata_path="${output_root}/run-metadata.json"
jq -n \
  --arg generatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg sourceFingerprint "$source_fingerprint" \
  --argjson originalScreenshotCount "$expected_original_count" \
  --argjson comparisonCount "$expected_comparison_count" \
  --slurpfile ios18 "$ios18_metadata" \
  --slurpfile ios26 "$ios26_metadata" \
  --slurpfile scenes "$scene_manifest" '
    {
      schemaVersion: 1,
      generatedAt: $generatedAt,
      sourceFingerprint: $sourceFingerprint,
      locale: "en-US",
      appearance: "light",
      widgetRenderingMode: "fullColor",
      ephemeralDevices: true,
      statusBarTime: "09:41",
      originalScreenshotCount: $originalScreenshotCount,
      comparisonCount: $comparisonCount,
      comparisonLayout: {
        gapPixels: 24,
        headerPixels: 180,
        encoding: "PNG",
        hasAlpha: false
      },
      runs: {
        "ios-18": $ios18[0],
        "ios-26": $ios26[0]
      },
      sceneManifest: $scenes[0],
      comparisons: [
        $scenes[0].deviceFamilies
        | to_entries[]
        | .key as $family
        | .value.scenes[]
        | {
            deviceFamily: $family,
            scene: .name,
            kind: .kind,
            widgetFamily: (.widgetFamily // null),
            ios18: (
              "originals/ios-18/" + $family + "/" + .name + ".png"
            ),
            ios26: (
              "originals/ios-26/" + $family + "/" + .name + ".png"
            ),
            composite: (
              "comparisons/" + $family + "/" + .name + ".png"
            )
          }
      ]
    }
  ' >"$metadata_path"

comparison_markdown="${output_root}/comparison.md"
{
  printf '%s\n' \
    '# Surround iOS 18 vs iOS 26' \
    '' \
    "Source fingerprint: \`${source_fingerprint}\`  " \
    "Xcode: $(jq -r '.xcodeVersion' "$ios18_metadata")  " \
    "Locale: en-US · Appearance: light · Status bar: 9:41" \
    ''

  for family in iphone ipad; do
    if [[ "$family" == "iphone" ]]; then
      section_title="iPhone 16 Pro Max — portrait"
    else
      section_title="iPad Pro 13-inch (M4) — landscape"
    fi
    printf '## %s\n\n' "$section_title"
    for kind in native widget; do
      if [[ "$kind" == "native" ]]; then
        kind_title="Native screens"
      else
        kind_title="Home-screen widgets"
      fi
      printf '### %s\n\n' "$kind_title"
      printf '%s\n' \
        '| Scene | iOS/iPadOS 18 | iOS/iPadOS 26 | Side-by-side |' \
        '| --- | --- | --- | --- |'
      awk -F '\t' \
        -v family="$family" \
        -v kind="$kind" \
        '$1 == family && $3 == kind { print $2 }' \
        "$comparison_records" \
        | while IFS= read -r scene; do
            printf '| `%s` | [PNG](originals/ios-18/%s/%s.png) | [PNG](originals/ios-26/%s/%s.png) | [Comparison](comparisons/%s/%s.png) |\n' \
              "$scene" "$family" "$scene" "$family" "$scene" "$family" "$scene"
          done
      printf '\n'
    done
  done
} >"$comparison_markdown"

gallery_path="${output_root}/index.html"
{
  printf '%s\n' \
    '<!doctype html>' \
    '<html lang="en">' \
    '<head>' \
    '  <meta charset="utf-8">' \
    '  <meta name="viewport" content="width=device-width, initial-scale=1">' \
    '  <title>Surround · iOS 18 vs iOS 26</title>' \
    '  <style>' \
    '    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }' \
    '    body { margin: 0 auto; max-width: 1800px; padding: 32px; }' \
    '    header { margin-bottom: 42px; }' \
    '    section { margin: 48px 0; }' \
    '    h3 { margin-top: 32px; }' \
    '    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 520px), 1fr)); gap: 28px; align-items: start; }' \
    '    figure { margin: 0; }' \
    '    img { display: block; width: 100%; height: auto; background: #eee; border-radius: 14px; box-shadow: 0 8px 30px rgb(0 0 0 / 18%); }' \
    '    figcaption { margin-top: 9px; overflow-wrap: anywhere; }' \
    '    .links { font-size: 0.85em; opacity: 0.78; }' \
    '    code { font-size: 0.9em; }' \
    '  </style>' \
    '</head>' \
    '<body>' \
    '<header>' \
    '  <h1>Surround · iOS 18 vs iOS 26</h1>'
  printf '  <p>%s originals · %s comparisons · en-US · light · 9:41 · source <code>%s</code></p>\n' \
    "$expected_original_count" "$expected_comparison_count" "$source_fingerprint"
  printf '%s\n' '</header>'

  for family in iphone ipad; do
    if [[ "$family" == "iphone" ]]; then
      section_title="iPhone 16 Pro Max · portrait · ${expected_iphone_count} pairs"
    else
      section_title="iPad Pro 13-inch (M4) · landscape · ${expected_ipad_count} pairs"
    fi
    printf '<section><h2>%s</h2>\n' "$section_title"
    for kind in native widget; do
      if [[ "$kind" == "native" ]]; then
        kind_title="Native screens"
      else
        kind_title="Home-screen widgets"
      fi
      printf '<h3>%s</h3><div class="grid">\n' "$kind_title"
      awk -F '\t' \
        -v family="$family" \
        -v kind="$kind" \
        '$1 == family && $3 == kind { print $2 }' \
        "$comparison_records" \
        | while IFS= read -r scene; do
            printf '  <figure><a href="comparisons/%s/%s.png"><img src="comparisons/%s/%s.png" loading="lazy" alt="%s comparison"></a><figcaption><strong>%s</strong><br><span class="links"><a href="originals/ios-18/%s/%s.png">18 original</a> · <a href="originals/ios-26/%s/%s.png">26 original</a></span></figcaption></figure>\n' \
              "$family" "$scene" "$family" "$scene" "$scene" "$scene" \
              "$family" "$scene" "$family" "$scene"
          done
      printf '%s\n' '</div>'
    done
    printf '%s\n' '</section>'
  done
  printf '%s\n' '</body>' '</html>'
} >"$gallery_path"

echo
echo "Captured ${expected_original_count} originals and produced ${expected_comparison_count} comparisons."
echo "Markdown: ${comparison_markdown}"
echo "Gallery:  ${gallery_path}"
echo "Metadata: ${metadata_path}"
